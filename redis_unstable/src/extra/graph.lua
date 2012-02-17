local math  = math
local Queue = require "Queue"
local Heap  = require "Heap"

--NOTE: Vset[] used by shortestpath()
Vset = {}; -- table(unique-list) of vertices

-- CONSTANTS CONSTANTS CONSTANTS CONSTANTS CONSTANTS CONSTANTS CONSTANTS
Direction           = {}; -- RELATIONSHIP Directions
Direction.OUTGOING  = 2;
Direction.INCOMING  = 1;
Direction.BOTH      = 0;

Uniqueness             = {};
Uniqueness.NODE_GLOBAL = 1;
Uniqueness.NONE        = 2;
Uniqueness.PATH_GLOBAL = 3;

Evaluation                      = {};
Evaluation.INCLUDE_AND_CONTINUE = 1;
Evaluation.INCLUDE_AND_PRUNE    = 2;
Evaluation.EXCLUDE_AND_CONTINUE = 3;
Evaluation.EXCLUDE_AND_PRUNE    = 4;

-- NODES NODES NODES NODES NODES NODES NODES NODES NODES NODES NODES NODES
local function createNode(tname, lo, pk)
  if     (lo      == nil) then error("createNode(x) - x does not exist");
  elseif (lo.node ~= nil) then error("createNode - Node already exists");
  elseif (pk      == nil) then error("createNode(x, pk) - pk not defined"); end
  lo.node       = { __pk=pk; __tname=tname; }
  Vset[lo.node] = true;
  --TODO add in __newindex to make lo.node READONLY
  --      (need bool in mod funcs to turn off/on READONLY)
  --     should also be recursively to lo.node.r[]
end
function createNamedNode(tname, lo, pk, name)
  createNode(tname, lo, pk); lo.node.__name = name;
end

function deleteNode(lo)
  if     (lo      == nil) then error("deleteNode(x) - x does not exist");
  elseif (lo.node == nil) then error("deleteNode - Node does not exists"); end
  Vset[lo.node] = nil;
  lo.node       = nil;
end

-- PROPERTIES PROPERTIES PROPERTIES PROPERTIES PROPERTIES PROPERTIES
function addNodeProperty(node, key, value)
  if     (node      == nil) then
    error("addNodePropery(x) - x does not exist");
  elseif (node[key] ~= nil) then
    error("addNodePropery(x, key) - key already exists");
  end
  node[key] = value;
end
function deleteNodeProperty(node, key)
  if     (node      == nil) then
    error("deleteNodePropery(x) - x does not exist");
  elseif (node[key] == nil) then
    error("deleteNodePropery(x, key) - key does not exists");
  end
  node[key] = nil;
end

-- RELATIONSHIPS RELATIONSHIPS RELATIONSHIPS RELATIONSHIPS RELATIONSHIPS
local function validateNodesInRel(snode, rtype, tnode)
  if     (snode      == nil)                                  then
    error("addNodeRelationShip(snode, ...) - snode does not exist");
  elseif (snode.__pk == nil)                                  then
    error("addNodeRelationShip(snode, ..., snode) - snode is not a NODE");
  elseif (tnode      == nil)                                  then
    error("addNodeRelationShip(snode, ..., tnode) - tnode does not exist");
  elseif (tnode.__pk == nil)                                  then
    error("addNodeRelationShip(snode, ..., tnode) - tnode is not a NODE");
  elseif (rtype      == nil)                                  then
    error("addNodeRelationShip(snode, rtype, ...) - rtype must be defined");
  end
end

function addNodeRelationShip(snode, rtype, tnode)
  validateNodesInRel(snode, rtype, tnode)
  local sd, td = 2, 1;
  if (snode.r            == nil) then snode.r            = {}; end
  if (snode.r[rtype]     == nil) then snode.r[rtype]     = {}; end
  if (snode.r[rtype][sd] == nil) then snode.r[rtype][sd] = {}; end
  if (tnode.r            == nil) then tnode.r            = {}; end
  if (tnode.r[rtype]     == nil) then tnode.r[rtype]     = {}; end
  if (tnode.r[rtype][td] == nil) then tnode.r[rtype][td] = {}; end
  snode.r[rtype][sd][tnode.__pk]        = {};
  snode.r[rtype][sd][tnode.__pk].target = tnode;
  tnode.r[rtype][td][snode.__pk]        = {};
  tnode.r[rtype][td][snode.__pk].target = snode;
end

local function isTableEmpty(t)
  for k,v in pairs(t) do return false; end
  return true;
end
local function reduceRel(snode, rtype, sd)
  if (isTableEmpty(snode.r[rtype][sd])) then
    snode.r[rtype][sd] = nil;
    if (isTableEmpty(snode.r[rtype])) then
      snode.r[rtype] = nil;
      if (isTableEmpty(snode.r)) then snode.r = nil; end
    end
  end
end
local function existsRel(snode, rtype, tnode, sd)
  if     (snode.r[rtype]     == nil) then
    error("snode does not have this relationship");
  elseif (snode.r[rtype][sd] == nil) then
    error("snode does not have this relationship in this direction");
  elseif (snode.r[rtype][sd][tnode.__pk] == nil) then
    error("snode does not have this relationship in this direction for tnode");
  end
end
function deleteNodeRelationShip(snode, rtype, tnode)
  validateNodesInRel(snode, rtype, tnode)
  local sd, td = 2, 1;
  existsRel(snode, rtype, tnode, sd);
  snode.r[rtype][sd][tnode.__pk] = nil; reduceRel(snode, rtype, sd);
  tnode.r[rtype][td][snode.__pk] = nil; reduceRel(tnode, rtype, td);
end

-- NOTE: example-usage: add weight to a relationship
function addPropertyToRelationship(snode, rtype, tnode, prop, value)
  validateNodesInRel(snode, rtype, tnode)
  local sd, td = 2, 1;
  existsRel(snode, rtype, tnode, sd);
  snode.r[rtype][sd][tnode.__pk][prop] = value;
  tnode.r[rtype][td][snode.__pk][prop] = value;
end

-- NEIGHBORHOOD NEIGHBORHOOD NEIGHBORHOOD NEIGHBORHOOD NEIGHBORHOOD
local function expanderOutgoing(x, rtype, relation)
  return (relation[Direction.OUTGOING] ~= nil), Direction.OUTGOING;
end
local function expanderIncoming(x, rtype, relation)
  return (relation[Direction.INCOMING] ~= nil), Direction.INCOMING;
end
local function expanderBoth(x, rtype, relation)
  return ((relation[Direction.INCOMING] ~= nil) or
          (relation[Direction.OUTGOING] ~= nil)), Direction.BOTH;
end
local function defaultExpanderFunc(x, rtype, relation)
  return expanderOutgoing(x, rtype, relation);
end

local function validateRelEvalFunc(doit, dir)
  assert(doit ~= nil           and dir ~= nil and
         dir >= Direction.BOTH and dir <= Direction.OUTGOING,
         "RelationEvaluationFuncs: return [yes,direction]");
end
local function getSingleNBhoodRel(t, x, rtype, relation, dir, nopts)
  local pkt = relation[dir];
  if (pkt == nil) then return; end
  for pk, trgt in pairs(pkt) do
    if     (nopts.rel_cost_func ~= nil) then 
      local pval = nopts.rel_cost_func(trgt);
      table.insert(t, pval, 
                   {node = trgt.target; rtype = rtype; relation = relation;});
    elseif (nopts.node_diff_func ~= nil) then 
      local pval = nopts.node_diff_func(x.w.node, trgt.target);
      table.insert(t, pval,
                   {node = trgt.target; rtype = rtype; relation = relation;});
    else
      table.insert(t,
                   {node = trgt.target; rtype = rtype; relation = relation;});
    end
  end
end
local function getNBhoodRel(x, nopts, t, rtype, relation)
    local doit, dir = nopts.expander_func(x, rtype, relation, x.w.node.r);
    validateRelEvalFunc(doit, dir);
    if (doit) then
      if (dir == Direction.BOTH) then
        getSingleNBhoodRel(t, x, rtype, relation, Direction.OUTGOING, nopts);
        getSingleNBhoodRel(t, x, rtype, relation, Direction.INCOMING, nopts);
      else
        getSingleNBhoodRel(t, x, rtype, relation, dir,                nopts);
      end
    end
end
local function getNeighborhood(x, nopts) 
  if (x.w.node.r == nil) then return {}; end
  local t = {};
  if (nopts.all_rel_expander_func ~= nil) then 
    local do_us = nopts.all_rel_expander_func(x, x.w.node.r);
    for k, v in pairs(do_us) do
      getNBhoodRel(x, nopts, t, v.rtype, v.relation);
    end
  else
    for rtype, relation in pairs(x.w.node.r) do
      getNBhoodRel(x, nopts, t, rtype, relation);
    end
  end
  return t;
end

-- OPTION_PARSING OPTION_PARSING OPTION_PARSING OPTION_PARSING OPTION_PARSING
local function getDepths(o)
  local mind, maxd = 0, math.huge;
  if (o ~= nil) then
    if (o.min_depth ~= nil) then mind = o.min_depth; end
    if (o.max_depth ~= nil) then maxd = o.max_depth; end
  end
  return {min = mind; max = maxd};
end
local function getUniqueness(o)
  if     (o == nil or o.uniqueness == nil) then
    return Uniqueness.NODE_GLOBAL;
  elseif (o.uniqueness == Uniqueness.NODE_GLOBAL or
          o.uniqueness == Uniqueness.NONE        or
          o.uniqueness == Uniqueness.PATH_GLOBAL) then return o.uniqueness;
  else error("Uniquness.[NODE_GLOBAL|NONE|PATH_GLOBAL]"); end
end
local function defaultEdgeEvalFunc(x)
  return Evaluation.INCLUDE_AND_CONTINUE;
end
local function getEdgeEvalFunc(o)
  if  (o == nil or o.edge_eval_func == nil) then
    return defaultEdgeEvalFunc;
  else
    return o.edge_eval_func;
  end
end
local function getExpanderFunc(o) 
  if  (o == nil or o.expander_func == nil) then
    return defaultExpanderFunc;
  else
    return o.expander_func;
  end
end
local function getEvalAllRelFunc(o)
  if  (o == nil or o.all_rel_expander_func == nil) then return nil; end
  return o.all_rel_expander_func;
end


-- TRAVERSERS TRAVERSERS TRAVERSERS TRAVERSERS TRAVERSERS TRAVERSERS TRAVERSERS
StartPK = 0; -- Used to Include/Exclude start-node

function getRelationText(rtype, relation)
  if (relation[Direction.OUTGOING] ~= nil) then
    return '-[' .. rtype .. ']->';
  else -- Direction.INCOMING
    return '<-[' .. rtype .. ']-';
  end
end
function getPath(x)
  local Q      = Queue.new();
  local parent = x.parent;
  while (parent ~= nil) do
    Q:insert(parent.w);
    local gparent = parent.parent;
    parent        = gparent;
  end
  local paths = '';
  while (not Q:isempty()) do
    local w = Q:retrieveFromEnd();
    if (string.len(paths) > 0) then
      paths = paths .. getRelationText(w.rtype, w.relation);
    end
    paths = paths .. w.node.__name;
  end
  if (string.len(paths) > 0) then
    paths = paths .. getRelationText(x.w.rtype, x.w.relation);
  end
  paths = paths .. x.w.node.__name;
  return paths;
end

local function isVirgin(u, x, vizd)
  local doit; local which;
  if     (u == Uniqueness.NODE_GLOBAL and not vizd[x.w.node]) then
    doit = true; which = x.w.node;
  elseif (u == Uniqueness.NONE)                             then
    doit = true; which = x.w.node;
  elseif (u == Uniqueness.PATH_GLOBAL)                      then
    if (x.parent == nil) then
      doit = true; which = 0;
    else --TODO '.' means direction is not specified
      which = x.parent.w.node.__name .. '.' .. x.w.node.__name;
      doit  = (not vizd[which]);
    end
  else
    doit = false;
  end
  return doit, which;
end

local function validateEvaled(eed)
  assert(eed >= Evaluation.INCLUDE_AND_CONTINUE and
         eed <= Evaluation.EXCLUDE_AND_PRUNE,
          "eval_func_must return Evaluation.*");
  local cont = (eed == Evaluation.INCLUDE_AND_CONTINUE) or
               (eed == Evaluation.EXCLUDE_AND_CONTINUE);
  local inc  = (eed == Evaluation.INCLUDE_AND_CONTINUE) or
               (eed == Evaluation.INCLUDE_AND_PRUNE);
  local prun = (eed == Evaluation.INCLUDE_AND_PRUNE) or
               (eed == Evaluation.EXCLUDE_AND_PRUNE);
  return cont, inc, prun;
end

-- REPLY_FUNC REPLY_FUNC REPLY_FUNC REPLY_FUNC REPLY_FUNC REPLY_FUNC
function rf_node_name    (x) return x.w.node.__name;                      end
function rf_path         (x) return getPath(x);                           end
function rf_node_and_path(x) return {node = x.w.node, path = getPath(x)}; end

-- BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS BFS
function traverse_bfs(v, reply_func, options)
  assert(Vset[v]    ~= nil, "node not in graph");
  assert(reply_func ~= nil, "arg: reply_func not defined");
  StartPK     = v.__pk;
  local d     = getDepths      (options);
  local u     = getUniqueness  (options);
  local evalf = getEdgeEvalFunc(options);
  local nopts = {expander_func         = getExpanderFunc(options);
                 all_rel_expander_func = getEvalAllRelFunc(options);}
  local vizd  = {}; -- control set
  local t     = {}; -- return table
  local Q     = Queue.new();
  local x     = {w = {node = v;}; parent = nil; depth = 1;};
  Q:insert(x);
  while (not Q:isempty()) do
    local x  = Q:retrieve();
    if (x.depth > d.max) then break; end
    local doit, which = isVirgin(u, x, vizd);
    if (doit) then
      vizd [which]          = true;
      local eed             = evalf(x);
      local cont, inc, prun = validateEvaled(eed)
      if (cont) then
        if (inc and x.depth >= d.min) then
          table.insert(t, reply_func(x));
        end
        if (not prun) then
          for k, w in pairs(getNeighborhood(x, nopts)) do
            local child = {w = w; parent = x; depth = (x.depth + 1);};
            local doity, whichy = isVirgin(u, child, vizd);
            if (doity) then Q:insert(child); end
          end
        end
      end
    end
  end
  return t;
end

-- DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS DFS
local function dfs_search(vizd, t, x, reply_func, d, u, nopts, evalf)
  local doit, which = isVirgin(u, x, vizd);
  if (doit) then
    vizd[which] = true
    local eed             = evalf(x);
    local cont, inc, prun = validateEvaled(eed)
    if (inc and x.depth >= d.min) then
      table.insert(t, reply_func(x));
    end
    if (x.depth >= d.max) then return; end
    if (cont) then
      for k, w in pairs(getNeighborhood(x, nopts)) do
        local child = {w = w; parent = x; depth = (x.depth + 1)};
        local doity, whichy = isVirgin(u, child, vizd);
        if (doity) then
          dfs_search(vizd, t, child, reply_func, d, u, nopts, evalf)
        end
      end
    end
  end
end
function traverse_dfs(v, reply_func, options)
  assert(Vset[v]    ~= nil, "node not in graph");
  assert(reply_func ~= nil, "arg: reply_func not defined");
  StartPK     = v.__pk;
  local d     = getDepths      (options);
  local u     = getUniqueness  (options);
  local evalf = getEdgeEvalFunc(options);
  local nopts = {expander_func         = getExpanderFunc(options);
                 all_rel_expander_func = getEvalAllRelFunc(options);}
  local vizd  = {}; -- control set
  local t     = {}; -- return table
  local x     = {w = {node = v;}; parent = nil; depth = 1;};
  dfs_search(vizd, t, x, reply_func, d, u, nopts, evalf)
  return t;
end

-- SHORTEST_PATH SHORTEST_PATH SHORTEST_PATH SHORTEST_PATH SHORTEST_PATH
function vertices() return next, Vset, nil end

function get_val_func(v) return v.cost; end

--TODO ProofOfConceptCode: this was a global shortestpath - for ALL nodes
--     then I quickly hacked on it, to make it for [FromStartNode->ToEndNode]
--     but it might be terribly INEFFICIENT on big-graphs
function shortestpath(snode, tnode, so_options)
  assert(Vset[snode]  ~= nil, "start-node not in graph");
  assert(Vset[tnode]  ~= nil, "end-node not in graph");
  StartPK     = snode.__pk;
  local min   = math.huge;
  local paths = {};
  local dist  = {};
  local nopts = {expander_func  = defaultExpanderFunc;
                 rel_cost_func  = so_options.relationship_cost_func;
                 node_diff_func = so_options.node_diff_func};
  local H     = Heap.new(get_val_func) -- keep unmarked vertices ordered by dist
  for u in vertices() do dist[u] = math.huge end
  dist[snode] = 0;
  for u, d in pairs(dist) do -- build heap
    H:insert(u, {w = {node = u;}; parent = nil; cost = d;})
  end
  while (not H:isempty()) do
    local u, x = H:retrieve()
    local du   = x.cost;
    if (u == tnode) then break; end
    for wt, w in pairs(getNeighborhood(x, nopts)) do
      local n  = w.node;
      local dn = dist[n];
      local d  = du + wt;
      if (d < min) then
        if (dn > d) then
          dist[n] = d;
          local path = {w = w; parent = x; cost = d;};
          paths[n] = path;
          if (n == tnode and d < min) then min = d; end
          H:update(n, path);
        end
      end
    end
  end
  return {cost = dist[tnode]; path=getPath(paths[tnode])};
end

-- DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG DEBUG
function debugPrintNameFromRel(v, rtype, direction)
  local nopts = {};
  if     (direction == Direction.INCOMING) then 
    nopts.expander_func = expanderIncoming;
  elseif (direction == Direction.OUTGOING) then
    nopts.expander_func = expanderOutgoing;
  elseif (direction == Direction.BOTH)     then
    nopts.expander_func = expanderBoth;
  else 
    error("Direction must be [Direction.INCOMING|OUTGOING|BOTH]");
  end
  local x = {w = {node = v;}; parent = nil; depth = 1;};
  for k, w in pairs(getNeighborhood(x, nopts)) do
    print ("\tPK: " .. k .. ' NAME: ' .. w.node.__name);
    if (w.weight) then print("\t\tWEIGHT: " .. w.weight); end
  end
end

