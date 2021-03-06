/*
 * This file implements the Query Optimiser for ALCHEMY_DATABASE
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

#ifndef __ALCHEMY_QUERY_OPTIMISER__H
#define __ALCHEMY_QUERY_OPTIMISER__H

#include "redis.h"

#include "join.h"
#include "alsosql.h"
#include "common.h"

//NOTE: used in join.c for MCI joins
bool promoteKLorFLtoW(cswc_t *w, list **klist, list **flist, bool freeme);

bool optimiseJoinPlan      (cli *c, jb_t *jb);
bool validateChain         (cli *c, jb_t *jb);

bool optimiseRangeQueryPlan(cli *c, cswc_t *w, wob_t *wb);

#endif /* __ALCHEMY_QUERY_OPTIMISER__H */ 
