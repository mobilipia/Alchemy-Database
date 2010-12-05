/*
 * This file implements the "NORMALIZE" commands
 *

GPL License

Copyright (c) 2010 Russell Sullivan <jaksprats AT gmail DOT com>
ALL RIGHTS RESERVED 

   This file is part of AlchemyDatabase

    AlchemyDatabase is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    AlchemyDatabase is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with AlchemyDatabase.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <assert.h>

#include "redis.h"

#include "bt_iterator.h"
#include "row.h"
#include "sql.h"
#include "index.h"
#include "rpipe.h"
#include "legacy.h"
#include "common.h"

// FROM redis.c
#define RL4 redisLog(4,
extern struct sharedObjectsStruct shared;

extern char *EQUALS;
extern char *COMMA;

extern char *Col_type_defs[];

// HELPER_COMMANDS HELPER_COMMANDS HELPER_COMMANDS HELPER_COMMANDS
// HELPER_COMMANDS HELPER_COMMANDS HELPER_COMMANDS HELPER_COMMANDS
static bool is_int(robj *pko) {
    char *endptr;
    long val = strtol(pko->ptr, &endptr, 10);
    val = 0; /* compiler warning */
    if (endptr[0] != '\0') return 0;
    else                   return 1;
}

/* this is a complicated failure scenario as NORM can fail
   AFTER creating several tables ... so it has succeeded and then FAILED */
#define NORM_MIDWAY_ERR_MSG "-ERR NORM command failed in the middle, error: "
static void handleTableCreationError(redisClient *c,
                                     redisClient *fc,
                                     robj        *lenobj,
                                     ulong        card) {
    listNode *ln     = listFirst(fc->reply);
    robj     *errmsg = ln->value;
    robj     *repl = createStringObject(NORM_MIDWAY_ERR_MSG,
                                        strlen(NORM_MIDWAY_ERR_MSG));
    repl->ptr      = sdscatlen(repl->ptr, errmsg->ptr, sdslen(errmsg->ptr));
    if (!lenobj) { /* no successful NORMed tables yet */
        INIT_LEN_OBJ
        lenobj->ptr = sdsnewlen(repl->ptr, sdslen(repl->ptr));
    } else {
        addReply(c, repl);
        lenobj->ptr = sdscatprintf(sdsempty(), "*%lu\r\n", card + 1);
    }
    decrRefCount(repl);
}

/* build response string (which are the table definitions) */
static robj *createNormRespStringObject(sds nt, robj *cdef) {
    robj *resp   = createStringObject("CREATE TABLE ", 13);
    resp->ptr    = sdscatlen(resp->ptr, nt, sdslen(nt));
    resp->ptr    = sdscatlen(resp->ptr, " (", 2);
    sds sql_cdef = sdsnewlen(cdef->ptr, sdslen(cdef->ptr));
    for (uint32 i = 0; i < sdslen(sql_cdef); i++) {
        if (sql_cdef[i] == '=') sql_cdef[i] = ' ';
    }
    resp->ptr    = sdscatlen(resp->ptr, sql_cdef, sdslen(sql_cdef));
    sdsfree(sql_cdef);
    resp->ptr    = sdscatlen(resp->ptr, ")", 1);
    return resp;
}

// NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM
// NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM NORM
static robj *makeWildcard(sds pattern, int plen, char *token, int token_len) {
    robj *r = createStringObject(pattern, plen);
    if (token_len) {
        r->ptr = sdscatlen(r->ptr, ":*:", 3);
        r->ptr = sdscatlen(r->ptr, token, token_len);
        r->ptr = sdscatlen(r->ptr, "*", 1);
    } else {
        r->ptr = sdscatlen(r->ptr, ":*", 2);
    }
    return r;
}
static robj *makeTblName(sds pattern, int plen, char *token, int token_len) {
    robj *r = createStringObject(pattern, plen);
    if (token_len) {
        r->ptr = sdscatlen(r->ptr, "_", 1);
        r->ptr = sdscatlen(r->ptr, token, token_len);
    }
    return r;
}

static void assignPkAndColToRow(robj *pko,
                                char *cname,
                                robj *valobj,
                                robj *cdefs[],
                                robj *rowvals[],
                                int  *nrows,
                                int   ep) {
    void *enc    = (void *)(long)valobj->encoding;
    /* If a string is an INT, we will store it as an INT */
    if (valobj->encoding == REDIS_ENCODING_RAW) {
        if (is_int(valobj)) enc = (void *)REDIS_ENCODING_INT;
    }

    robj      *col   = createStringObject(cname, strlen(cname));
    dictEntry *cdef  = dictFind((dict *)cdefs[ep]->ptr, col);
    if (!cdef) {                                /* new column */
        dictAdd((dict *)cdefs[ep]->ptr, col, enc);
    } else {                                    /* known column */
        void *cenc = cdef->val;
        if (cenc == (void *)REDIS_ENCODING_INT) { /* check enc */
            if (cenc != enc) { /* string in INT col -> TEXT col */
                dictReplace((dict *)cdefs[ep]->ptr, col, enc);
            }
        }
    }

    dictEntry *row  = dictFind((dict *)rowvals[ep]->ptr, pko);
    if (!row) {         /* row does not yet have columns defined */
        *nrows = *nrows + 1;
        robj *set = createSetObject();
        dictAdd((dict *)set->ptr,       col, valobj);
        dictAdd((dict *)rowvals[ep]->ptr, pko, set);
    } else {            /* row has at least one column defined */
        robj      *set  = row->val;
        dictAdd((dict *)set->ptr, col, valobj);
    }
}

#define MAX_NUM_NORM_TBLS 16
void normCommand(redisClient *c) {
    robj   *new_tbls[MAX_NUM_NORM_TBLS];
    robj   *ext_patt[MAX_NUM_NORM_TBLS];
    uint32  ext_len [MAX_NUM_NORM_TBLS];
    sds     pattern = c->argv[1]->ptr;
    int     plen    = sdslen(pattern);
    int     n_ep    = 0;

    /* First: create wildcards and their destination tablenames */
    if (c->argc > 2) {
        sds   start = c->argv[2]->ptr; 
        char *token = start;
        char *nextc = start;
        while ((nextc = strchr(nextc, ','))) {
            ext_patt[n_ep] = makeWildcard(pattern, plen, token, nextc - token);
            ext_len [n_ep] = sdslen(ext_patt[n_ep]->ptr);
            new_tbls[n_ep] = makeTblName( pattern, plen, token, nextc - token);
            n_ep++;
            nextc++;
            token          = nextc;
        }
        int token_len  = sdslen(start) - (token - start);
        ext_patt[n_ep] = makeWildcard(pattern, plen, token, token_len);
        ext_len [n_ep] = sdslen(ext_patt[n_ep]->ptr);
        new_tbls[n_ep] = makeTblName( pattern, plen, token, token_len);
        n_ep++;
    }
    ext_patt[n_ep] = makeWildcard(pattern, plen, NULL, 0);
    sds e          = ext_patt[n_ep]->ptr;
    ext_len [n_ep] = strrchr(e, ':') - e + 1;
    new_tbls[n_ep] = makeTblName( pattern, plen, NULL, 0);
    n_ep++;

    robj  *cdefs   [MAX_NUM_NORM_TBLS];
    robj  *rowvals [MAX_NUM_NORM_TBLS];
    uchar  pk_type [MAX_NUM_NORM_TBLS];
    for (int i = 0; i < n_ep; i++) {
        cdefs  [i] = createSetObject();
        rowvals[i] = createSetObject();
        pk_type[i] = COL_TYPE_INT;
    }

    struct redisClient *fc = NULL; /* must come before first GOTO */

    /* Second: search ALL keys and create column_definitions for wildcards */
    dictEntry    *de;
    int           nrows = 0;
    dictIterator *di = dictGetIterator(c->db->dict);
    while((de = dictNext(di)) != NULL) {                   /* search ALL keys */
        robj *keyobj = dictGetEntryKey(de);
        sds   key    = keyobj->ptr;
        for (int i = 0; i < n_ep; i++) {
            sds e = ext_patt[i]->ptr;
            if (stringmatchlen(e, sdslen(e), key, sdslen(key), 0)) { /* MATCH */
                robj *val    = dictGetEntryVal(de);
                char *pk     = strchr(key, ':');
                if (!pk) goto norm_end;
                pk++;
                char *end_pk = strchr(pk, ':');
                int   pklen  = end_pk ? end_pk - pk : (int)strlen(pk);
                robj *pko    = createStringObject(pk, pklen);
                /* a single STRING means the PK is TEXT */
                if (!is_int(pko)) pk_type[i] = COL_TYPE_STRING;

                if (val->type == REDIS_HASH) { /* each hash key is a colname */
                    hashIterator *hi = hashInitIterator(val);
                    while (hashNext(hi) != REDIS_ERR) {
                        robj *hkey = hashCurrent(hi, REDIS_HASH_KEY);
                        robj *hval = hashCurrent(hi, REDIS_HASH_VALUE);
                        assignPkAndColToRow(pko, hkey->ptr, hval,
                                            cdefs, rowvals, &nrows, i);
                    }
                    hashReleaseIterator(hi);
                    break; /* match FIRST ext_patt[] */
                } else if (val->type == REDIS_STRING) {
                    char *cname;
                    if (i == (n_ep - 1)) { /* primary key */
                        cname = strchr(key + ext_len[i], ':');
                        if (!cname) goto norm_end;
                        cname++;
                    } else {
                        /* 2ndary matches of REDIS_STRINGs MUST have the format
                            "primarywildcard:pk:secondarywildcard:columnname" */
                        if (sdslen(key) <= (ext_len[i] + 1) || /* ":" -> +1 */
                            key[ext_len[i] - 1] != ':') {
                            decrRefCount(pko);
                            continue;
                        }
                        cname = key + ext_len[i];
                    }
                    assignPkAndColToRow(pko, cname, val,
                                         cdefs, rowvals, &nrows, i);
                    break; /* match FIRST ext_patt[] */
                }
            }
        }
    }
    dictReleaseIterator(di);

    if (!nrows) {
        addReply(c, shared.czero);
        goto norm_end;
    }

    robj *argv[STORAGE_MAX_ARGC + 1];
    fc       = rsql_createFakeClient();
    fc->argv = argv;

    EMPTY_LEN_OBJ
    for (int i = 0; i < n_ep; i++) {
        dictEntry    *de, *ide;
        dictIterator *di, *idi;
        /* Third: CREATE TABLE with column definitions from Step 2*/
        sds   nt   = new_tbls[i]->ptr;
        bool  cint = (pk_type[i] == COL_TYPE_STRING);
        robj *cdef = cint ?  createStringObject("pk=TEXT", 7) :
                             createStringObject("pk=INT",  6); 
        di         = dictGetIterator(cdefs[i]->ptr);
        while((de = dictNext(di)) != NULL) {
            robj *key = de->key;
            long  enc = (long)de->val;
            cdef->ptr = sdscatprintf(cdef->ptr, "%s%s%s%s",
                                      COMMA, (char *)key->ptr,
                                      EQUALS, Col_type_defs[enc]);
        }
        dictReleaseIterator(di);

        robj *resp  = createNormRespStringObject(nt, cdef);
        fc->argv[1] = createStringObject(nt, sdslen(nt));
        fc->argv[2] = cdef;
        fc->argc    = 3;

        rsql_resetFakeClient(fc);
        legacyTableCommand(fc);
        if (!respOk(fc)) { /* most likely table already exists */
            handleTableCreationError(c, fc, lenobj, card);
            goto norm_end;
        }
        decrRefCount(cdef);

        /* Fourth: INSERT INTO new_table with rows from Step 2 */
        di = dictGetIterator(rowvals[i]->ptr);
        while((de = dictNext(di)) != NULL) {
            robj *key  = de->key;
            robj *val  = de->val;
            /* create SQL-ROW from key & loop[vals] */
            robj *ir   = createStringObject(key->ptr, sdslen(key->ptr));
            dict *row  = (dict*)val->ptr;
            idi        = dictGetIterator(cdefs[i]->ptr);
            while((ide = dictNext(idi)) != NULL) {
                ir->ptr         = sdscatlen(ir->ptr, COMMA, 1);
                robj      *ckey = ide->key;
                dictEntry *erow = dictFind(row, ckey);
                if (erow) {
                    robj *cval = erow->val;
                    void *cvp  = cval->ptr;
                    bool rwenc = (cval->encoding != REDIS_ENCODING_RAW);
                    ir->ptr = rwenc ? sdscatprintf(ir->ptr, "%ld", (long)(cvp)):
                                      sdscatlen(   ir->ptr, cvp,   sdslen(cvp));
                }
            }
            dictReleaseIterator(idi);

            fc->argv[1] = createStringObject(nt, sdslen(nt));
            fc->argv[2] = ir;
            fc->argc    = 3;
            rsql_resetFakeClient(fc);
            legacyInsertCommand(fc);
            if (!respOk(fc)) { /* INSERT fail [unsecaped , or )] */
                handleTableCreationError(c, fc, lenobj, card);
                dictReleaseIterator(di);
                decrRefCount(resp);
                decrRefCount(ir);
                goto norm_end;
            }
            decrRefCount(ir);
        }
        dictReleaseIterator(di);

        if (!lenobj) {
            INIT_LEN_OBJ
        }
        addReplyBulk(c, resp);
        decrRefCount(resp);
        card++;
    }
    lenobj->ptr = sdscatprintf(sdsempty(), "*%lu\r\n", card);

norm_end:
    for (int i = 0; i < n_ep; i++) {
        decrRefCount(new_tbls[i]);
        decrRefCount(ext_patt[i]);
        decrRefCount(cdefs   [i]);
        decrRefCount(rowvals [i]);
    }
    if (fc) rsql_freeFakeClient(fc);
}
