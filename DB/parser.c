/*
 * This file implements  parsing functions
 *

AGPL License

Copyright (c) 2011 Russell Sullivan <jaksprats AT gmail DOT com>
ALL RIGHTS RESERVED 

   This file is part of ALCHEMY_DATABASE

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as
    published by the Free Software Foundation, either version 3 of the
    License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <ctype.h>

#include "redis.h"
#include "zmalloc.h"

#include "colparse.h"
#include "row.h"
#include "parser.h"

/* copy of strdup - compiles w/o warnings */
inline char *_strdup(char *s) {
    int len = strlen(s);
    char *x = malloc(len + 1);
    memcpy(x, s, len); x[len]  = '\0';
    return x;
}

inline char *_strnchr(char *s, int c, int len) {
    for (int i = 0; i < len; i++) {
        if (*s == c) return s;
        s++;
    }
    return NULL;
}

// HELPERS HELPERS HELPERS HELPERS HELPERS HELPERS HELPERS HELPERS HELPERS
char *DXDB_strcasestr(char *haystack, char *needle) {
    char *p, *startn = 0, *np = 0;
    for (p = haystack; *p; p++) {
        if (np) {
            if (toupper(*p) == toupper(*np)) {
                if (!*++np) return startn;
            } else np = 0;
        } else if (toupper(*p) == toupper(*needle)) {
            np = needle + 1;
            startn = p;
        }
    }
    return 0;
}

robj *_createStringObject(char *s) {
    return createStringObject(s, strlen(s));
}

robj *cloneRobj(robj *r) { // must be decrRefCount()ed
    if (!r) return NULL;
    if (EREDIS) return cloneRobjErow(r);
    else {
        if (r->encoding == REDIS_ENCODING_RAW) {
            return createStringObject(r->ptr, sdslen(r->ptr));
        } else {        /* REDIS_ENCODING_INT */
            robj *n     = createObject(REDIS_STRING, r->ptr);
            n->encoding = REDIS_ENCODING_INT;
            return n;
        }
    }
}
void destroyCloneRobj(robj *r) {
    if (!r) return;
    if (EREDIS) decrRefCountErow(r);
    else        decrRefCount(r);
}

robj **copyArgv(robj **argv, int argc) {
    robj **cargv = zmalloc(sizeof(robj*)*argc);
    for (int j = 0; j < argc; j++) {
        cargv[j] = createObject(REDIS_STRING, argv[j]->ptr);
    }
    return cargv;
}

char *rem_backticks(char *token, int *len) {
    char *otoken = token;
    int   olen   = *len;
    if (*token == '`') { token++;  *len = *len - 1; }
    if (otoken[olen - 1] == '`') { *len = *len - 1; }
    return token;
}


// TYPE_CHECK TYPE_CHECK TYPE_CHECK TYPE_CHECK TYPE_CHECK TYPE_CHECK
//TODO "if (endptr && !*endptr)" is a better check
bool is_int(char *s) { // Used in UPDATE EXPRESSIONS
    char *endptr; long val = strtol(s, &endptr, 10);
    (void)val; // compiler warning
    if (endptr[0] != '\0') return 0;
    else                   return 1;
}

bool is_u128(char *s) { // Used in UPDATE EXPRESSIONS
    uint128 x; return parseU128(s, &x);
}
bool is_float(char *s) { // Used in UPDATE EXPRESSIONS
    char *endptr; double val = strtod(s, &endptr);
    (void)val; // compiler warning
    if (endptr[0] != '\0') return 0;
    else                   return 1;
}

bool is_text(char *beg, int len) { // Used in assignMisses for simple UPDATEs
    char *s = beg; char dlm;
    if      (*s == '\'') dlm = '\'';
    else if (*s == '"')  dlm = '"';
    else return 0;
    s++;
    s = strn_next_unescaped_chr(s, s, dlm, (len - 1));
    if (!s) return 0;
    if ((s - beg) == (len - 1)) return 1;
    else                        return 0;
}

// GEN_1_WC_PARSE GEN_1_WC_PARSE GEN_1_WC_PARSE GEN_1_WC_PARSE GEN_1_WC_PARSE
char *extract_string_col(char *start, int *len) { //NOTE: used in pRangeReply()
    if (*start == '\'') { /* ignore leading \' in string col */
        start++; DECR(*len)
        if (*(start + *len - 1) == '\'') DECR(*len)
        else                             return NULL;
    }
    return start;
}
//NOTE: used in parseWC()
char *strcasestr_blockchar(char *haystack, char *needle, char blockchar) {
    char *bstart       = haystack;
    while (1) {
        char *found    = DXDB_strcasestr(bstart, needle);
        if (!found)         return NULL;
        while (1) {
            bstart     = str_next_unescaped_chr(bstart, bstart, blockchar);
            if (!bstart)        return found; /* no block */
            if (bstart > found) return found; /* block after found */
            bstart++;
            char *bend = str_next_unescaped_chr(bstart, bstart, blockchar);
            if (!bend)          return NULL; /* block doesnt end */
            bstart     = bend + 1;
            if (bstart >= found) break;      /* found w/in block, look again */
        }
    }
}
char *next_token_wc_key(char *tkn, uchar ctype) {
    if (C_IS_S(ctype)) {
        if (*tkn != '\'') return NULL;
        tkn++; /* skip leading  \' */
        tkn = str_next_unescaped_chr(tkn, tkn, '\'');
        if (!tkn)         return NULL;
        tkn++; /* skip trailing \' */
    } else {
        tkn = strchr(tkn, ' ');
    }
    return tkn;
}

static char *_strn_next_unescaped_chr(char *beg, char *s, int x, int len) {
    bool  isn   = (len >= 0);
    char *nextc = (s + 1); // ignore first character
    while (1) {
        nextc = isn ? _strnchr(nextc, x, len) : strchr(nextc, x);
        if (!nextc) break;
        if (nextc != beg) {  /* skip first character */
            if  (*(nextc - 1) == '\\') { /* handle backslash-escaped commas */
                char *backslash = nextc - 1;
                while (backslash >= beg) {
                    if (*backslash != '\\') break;
                    backslash--;
                }
                int num_backslash = nextc - backslash - 1;
                if (num_backslash % 2 == 1) {
                    nextc++; continue;
                }
            }
        }
        return nextc;
    }
    return NULL;
}
char *str_next_unescaped_chr(char *beg, char *s, int x) {
    return _strn_next_unescaped_chr(beg, s, x, -1);
}
char *strn_next_unescaped_chr(char *beg, char *s, int x, int len) {
    return _strn_next_unescaped_chr(beg, s, x, len);
}
static char *str_matching_end_delim(char *beg, char sdelim, char fdelim) {
    int   n_open_delim = 0;
    char *x            = beg;
    while (*x) {
        if (     *x == sdelim) n_open_delim++;
        else if (*x == fdelim) n_open_delim--;
        if (x != beg && !n_open_delim) return x;
        x++;
    }
    return NULL;
}
char *str_matching_end_paren(char *beg) { //NOTE: used in checkIN_Clause()
    return str_matching_end_delim(beg, '(', ')');
}

/* PARSER PARSER PARSER PARSER PARSER PARSER PARSER PARSER PARSER PARSER */
/* *_token*() make up the primary c->argv[]->ptr parser */
char *next_token(char *nextp) {
    char *p = strchr(nextp, ' ');
    if (!p) return NULL;
    while (ISBLANK(*p)) p++;
    return *p ? p : NULL;
}
int get_token_len(char *tok) {
    char *x = strchr(tok, ' ');
    return x ? x - tok : (int)strlen(tok);
}

//NOTE: used by pWC_checkLuaFunc() & parseOBYcol() 
inline char *strstr_not_quoted(char *h, char *n) {
    int nlen = strlen(n);
    while (*h) {
        if (*h == '\'') h = str_next_unescaped_chr(h, h, '\'');
        if (!strncmp(h, n, nlen)) return h;
        h++;
    }
    return NULL;
}
inline char *get_after_parens(char *p) { //NOTE used by isLuaFunc()
    int parens = 0;
    while (*p) {
        if      (*p == '(')  parens++;
        else if (*p == ')')  parens--;
        else if (*p == '\'') p = str_next_unescaped_chr(p, p, '\'');
        if (!parens) return p;
        p++;
    }
    return NULL;
}
char *get_next_nonparaned_comma(char *tkn) {
    SKIP_SPACES(tkn)
    if (*tkn == '\'') tkn = str_next_unescaped_chr(tkn, tkn, '\'');
    char *z = strchr(tkn, ','); if (!z) return NULL;
    char *p = strchr(tkn, '(');
    if (p && p < z) {
        char *y = get_after_parens(p);
        if (y) return strchr(y, ',');
        else   return NULL;
    } else return z;
}
char *get_next_insert_value_token(char *tkn) {
    SKIP_SPACES(tkn)
    while (*tkn) {
        if      (*tkn == '\'') tkn = str_next_unescaped_chr(tkn, tkn, '\'');
        else if (*tkn == '(' ) tkn = str_next_unescaped_chr(tkn, tkn, ')');
        else if (*tkn == '{' ) tkn = str_next_unescaped_chr(tkn, tkn, '}');
        else if (*tkn == ',' ) return tkn;
        if (!tkn) return NULL;
        tkn++;
    }
    return NULL;
}

/* PIPE_PARSING PIPE_PARSING PIPE_PARSING PIPE_PARSING PIPE_PARSING */
robj **parseScanCmdToArgv(char *as_cmd, int *argc) {
    int    rargc;
    robj **rargv = NULL;
    sds   *argv  = sdssplitlen(as_cmd, strlen(as_cmd), " ", 1, &rargc);
    /* all errors -> GOTO */
    if (rargc < 4)                     goto parse_scan_2argv_end;
    bool is_sel;
    if (     !strcasecmp(argv[0], "SCAN"))   is_sel = 0;
    else if (!strcasecmp(argv[0], "SELECT")) is_sel = 1;
    else                               goto parse_scan_2argv_end;

    if (is_sel && rargc < 6)           goto parse_scan_2argv_end;
    int j;
    for (j = 1; j < rargc; j++) {
        if (!strcasecmp(argv[j], "FROM")) break;
    }
    if ((j == (rargc -1)) || (j == 1)) goto parse_scan_2argv_end;
    int k;
    bool nowc_oby = 0;
    for (k = j + 1; k < rargc; k++) {
        if (!strcasecmp(argv[k], "WHERE")) break;
        if (!strcasecmp(argv[k], "ORDER")) {
            nowc_oby = 1;
            break;
        }
    }
    if (is_sel && nowc_oby) goto parse_scan_2argv_end; /* SELECT needs WHERE */
    if ((k == (j + 1)))     goto parse_scan_2argv_end; /* FROM WHERE */
    if ((k == (rargc - 1))) goto parse_scan_2argv_end; /* .... WHERE */
    bool nowc = (k == rargc); /* k loop did not fidn "WHERE" */
    if (is_sel && nowc)     goto parse_scan_2argv_end; /* SELECT needs WHERE */

    /* parsing is OK, time to zmalloc and set argc -> no more GOTOs */
    if (nowc)          *argc = 4;
    else if (nowc_oby) *argc = 5;
    else               *argc = 6;
    rargv      = zmalloc(sizeof(robj *) * *argc);
    rargv[0]   = is_sel ?  createStringObject("SELECT", 6) :
                           createStringObject("SCAN",   4);
    sds clist  = sdsempty();
    for (int i = 1; i < j; i++) {
        if (sdslen(argv[i])) {
            if (sdslen(clist)) clist = sdscatlen(clist, ",", 1);
            clist = sdscatlen(clist, argv[i], sdslen(argv[i]));
        }
    }
    rargv[1]   = createObject(REDIS_STRING, clist);
    rargv[2]   = createStringObject("FROM",   4);
    sds tlist  = sdsempty();
    for (int i = j + 1; i < k; i++) {
        if (sdslen(argv[i])) {
            if (sdslen(tlist)) tlist = sdscatlen(tlist, ",", 1);
            tlist = sdscatlen(tlist, argv[i], sdslen(argv[i]));
        }
    }
    rargv[3]   = createObject(REDIS_STRING, tlist);

    if (!nowc) {
        if (nowc_oby) {
            sds oby    = sdsnewlen("ORDER ", 6);
            for (int i = k + 1; i < rargc; i++) {
                if (sdslen(argv[i])) {
                    if (sdslen(oby)) oby = sdscatlen(oby, " ", 1);
                    oby = sdscatlen(oby, argv[i], sdslen(argv[i]));
                }
            }
            rargv[4]   = createObject(REDIS_STRING, oby);
        } else {
            rargv[4]   = createStringObject("WHERE",  5);
            sds wc     = sdsempty();
            for (int i = k + 1; i < rargc; i++) {
                if (sdslen(argv[i])) {
                    if (sdslen(wc)) wc = sdscatlen(wc, " ", 1);
                    wc = sdscatlen(wc, argv[i], sdslen(argv[i]));
                }
            }
            rargv[5]   = createObject(REDIS_STRING, wc);
        }
    }

parse_scan_2argv_end:
    for (int i = 0; i < rargc; i++) sdsfree(argv[i]);
    zfree(argv);
    return rargv;
}
