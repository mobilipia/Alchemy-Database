/*
 * This file implements the "SCAN"
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

#include "redis.h"

#include "debug.h"
#include "embed.h"
#include "bt_iterator.h"
#include "wc.h"
#include "qo.h"
#include "orderby.h"
#include "filter.h"
#include "index.h"
#include "colparse.h"
#include "range.h"
#include "find.h"
#include "aobj.h"
#include "alsosql.h"

extern r_tbl_t *Tbl; // used in getBtr()
extern uchar    OutputMode;

static void scanJoin(cli *c) {
    aobj aL, aH;
    jb_t jb;
    init_join_block(&jb);
    if (!parseJoinReply(c, &jb, c->argv[1]->ptr, c->argv[3]->ptr,
                        c->argv[5]->ptr))                          goto sj_end;
    int  least_cnt = -1; f_t *lflt = NULL;
    for (int k = 0; k < (int)jb.n_jind; k++) {
        int cnt = getBtr(jb.ij[k].lhs.tmatch)->numkeys;
        if (least_cnt == -1 ||  cnt < least_cnt) {
            least_cnt = cnt; lflt = &jb.ij[k].lhs;
        }
        if (jb.ij[k].lhs.tmatch != jb.ij[k].rhs.tmatch) {
            cnt = getBtr(jb.ij[k].rhs.tmatch)->numkeys;
            if (cnt < least_cnt) {
                least_cnt = cnt; lflt = &jb.ij[k].rhs;
            }
        }
    }
    bt  *btr       = getBtr(lflt->tmatch);
    if (!assignMinKey(btr, &aL))                                   goto sj_end;
    if (!assignMaxKey(btr, &aH))                                   goto sj_end;
    ijp_t *ij = &jb.ij[jb.n_jind];
    init_ijp(ij);
    ij->lhs.jan    = lflt->jan;
    ij->lhs.imatch = find_index(lflt->tmatch, 0); /* PK RQ */
    ij->lhs.tmatch = lflt->tmatch;
    ij->lhs.cmatch = 0;                           /* PK RQ */
    ij->lhs.op     = RQ;                          /* PK RQ */
    ij->lhs.low    = createSDSFromAobj(&aL);
    ij->lhs.high   = createSDSFromAobj(&aH);
    jb.n_jind++;

    bool ok = optimiseJoinPlan(c, &jb) && validateChain(c, &jb);
    if (ok) {
        if (c->Explain) explainJoin(c, &jb); 
        else {
            if (EREDIS) embeddedSaveJoinedColumnNames(&jb);
            executeJoin(c, &jb);
        }
    }

sj_end:
    destroy_join_block(c, &jb);
}

/* SYNTAX
   1.) SCAN * FROM tbl
   2.) SCAN * FROM tbl ORDER_BY_CLAUSE
   3.) SCAN * FROM tbl WHERE clause [ORDER_BY_CLAUSE]
*/
void tscanCommand(redisClient *c) { //printf("tscanCommand\n");
    aobj aL, aH;
    list *cmatchl = listCreate();
    bool  nowc    =  0; /* NO WHERE CLAUSE */
    bool  cstar   =  0;
    int   qcols   =  0;
    int   tmatch  = -1;
    bool  join    =  0;
    sds   where   = (c->argc > 4) ? c->argv[4]->ptr : NULL;
    sds   wc      = (c->argc > 5) ? c->argv[5]->ptr : NULL;
    if ((where && !*where) || (wc && !*wc)) {
        addReply(c, shared.scansyntax);  listRelease(cmatchl); return;
    }
    if (!parseSelect(c, 1, &nowc, &tmatch, cmatchl, &qcols, &join,
                     &cstar, c->argv[1]->ptr, c->argv[2]->ptr,
                     c->argv[3]->ptr, where)) { listRelease(cmatchl); return; }
    if (!nowc && !wc) {
        addReply(c, shared.scansyntax); listRelease(cmatchl); return;
    }
    if (join) { scanJoin(c); listRelease(cmatchl); return; }
    CMATCHS_FROM_CMATCHL

    c->LruColInSelect = initLRUCS(tmatch, cmatchs, qcols);
    cswc_t w; wob_t wb;
    init_check_sql_where_clause(&w, tmatch, wc); /* on error: GOTO tscan_end */
    init_wob(&wb);

    if (nowc && c->argc > 4) { /* ORDER BY w/o WHERE CLAUSE */
        if (!strncasecmp(where, "ORDER ", 6)) {
            if (!parseWCEnd(c, c->argv[4]->ptr, &w, &wb))      goto tscan_end;
            if (w.lvr) {
                w.lvr = sdsnewlen(w.lvr, strlen(w.lvr));
                if (!leftoverParsingReply(c, w.lvr))           goto tscan_end;
            }
        }
    }
    if (nowc && !wb.nob && c->argc > 4) { /* argv[4] parse error */
        w.lvr = sdsdup(where); leftoverParsingReply(c, w.lvr); goto tscan_end;
    }
    if (!nowc && !wb.nob) { /* WhereClause exists and no ORDER BY */
        uchar prs = parseWC(c, &w, &wb, NULL, NULL);
        if (prs == PARSE_GEN_ERR) {
            addReply(c, shared.scansyntax);                    goto tscan_end;
        }
        if (prs == PARSE_NEST_ERR)                             goto tscan_end;
        if (!leftoverParsingReply(c, w.lvr))                   goto tscan_end;
    }
    if (cstar && wb.nob) { /* SCAN COUNT(*) ORDER BY -> stupid */
        addReply(c, shared.orderby_count);                     goto tscan_end;
    }

    bt *btr = getBtr(w.wf.tmatch);
    if (cstar && nowc) { /* SCAN COUNT(*) FROM tbl */
        addReplyLongLong(c, (long long)btr->numkeys);          goto tscan_end;
    }
    if (!assignMinKey(btr, &aL) || !assignMaxKey(btr, &aH)) {
        addReply(c, shared.nullbulk);                          goto tscan_end;
    }
    w.wf.alow   = aL;
    w.wf.ahigh  = aH;
    w.wf.imatch = find_index(w.wf.tmatch, 0);
    w.wf.cmatch = 0; /* PK RangeQuery */
    w.wtype     = SQL_RANGE_LKP; //dumpW(printf, &w);
    convertFilterListToAobj(w.flist);
    if (c->Explain) explainRQ(c, &w, &wb);
    else {
        if (EREDIS) embeddedSaveSelectedColumnNames(tmatch, cmatchs, qcols);
        iselectAction(c, &w, &wb, cmatchs, qcols, cstar);
    }

tscan_end:
    listRelease(cmatchl); destroy_wob(&wb); destroy_check_sql_where_clause(&w);
}
