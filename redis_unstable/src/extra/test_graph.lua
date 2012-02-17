
-- TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST TEST
function dump_node_and_path(z)
  local i = 1;
  for k,v in pairs(z) do
    print("\t" .. i .. ': NAME: ' .. v.node.__name .. "\tPATH: " .. v.path);
    i = i + 1;
  end
end

-- INITIAL INITIAL INITIAL INITIAL INITIAL INITIAL INITIAL INITIAL INITIAL
function initial_test()
  V = {};
  local tbl = 'users';
  V.lo1 = {}; createNamedNode(tbl, V.lo1, 11, 'Joe1');
  V.lo2 = {}; createNamedNode(tbl, V.lo2, 22, 'Bill2');
  V.lo3 = {}; createNamedNode(tbl, V.lo3, 33, 'Jane3');
  V.lo4 = {}; createNamedNode(tbl, V.lo4, 44, 'Ken4');
  V.lo5 = {}; createNamedNode(tbl, V.lo5, 55, 'Kate5');
  V.lo6 = {}; createNamedNode(tbl, V.lo6, 65, 'Mack6');
  V.lo7 = {}; createNamedNode(tbl, V.lo7, 77, 'Lyle7');
  V.lo8 = {}; createNamedNode(tbl, V.lo8, 88, 'Bud8');
  V.lo9 = {}; createNamedNode(tbl, V.lo9, 99, 'Rick9');
  V.loa = {}; createNamedNode(tbl, V.loa, 12, 'Lori9');
  addNodeRelationShip(V.lo1.node, 'LIKES', V.lo2.node);
  addNodeRelationShip(V.lo2.node, 'KNOWS', V.lo1.node);
  addNodeRelationShip(V.lo2.node, 'KNOWS', V.lo3.node);
  addNodeRelationShip(V.lo3.node, 'KNOWS', V.lo4.node);
  addNodeRelationShip(V.lo4.node, 'KNOWS', V.lo5.node);
  addNodeRelationShip(V.lo2.node, 'KNOWS', V.lo6.node);
  addNodeRelationShip(V.lo6.node, 'KNOWS', V.lo7.node);
  addNodeRelationShip(V.lo1.node, 'KNOWS', V.lo8.node);
  addNodeRelationShip(V.lo8.node, 'KNOWS', V.lo9.node);
  addNodeRelationShip(V.lo4.node, 'KNOWS', V.loa.node);

  print ('2 matches: KNOWS: 8 BOTH');
  debugPrintNameFromRel(V.lo8.node, 'KNOWS', Direction.BOTH);

  print ('3 matches: KNOWS: 2 OUT');
  debugPrintNameFromRel(V.lo2.node, 'KNOWS', Direction.OUTGOING);
  print ('1 match: LIKE: 2 IN');
  debugPrintNameFromRel(V.lo2.node, 'LIKES', Direction.INCOMING);

  deleteNodeRelationShip(V.lo1.node, 'LIKES', V.lo2.node);
  print ('0 matches: LIKE: 2 IN - deleted');
  debugPrintNameFromRel(V.lo2.node, 'LIKES', Direction.INCOMING);

  addPropertyToRelationship(V.lo2.node, 'KNOWS', V.lo3.node, 'weight', 10);
  print ('3 matches: KNOWS: 2 OUT - one w/ weight');
  debugPrintNameFromRel(V.lo2.node, 'KNOWS', Direction.OUTGOING);

  local x = traverse_bfs(V.lo2.node, rf_path);
  print('BreadthFirst: rf_path');
  for k,v in pairs(x) do print("\tPATH: " .. v); end

  local y = traverse_bfs(V.lo2.node, rf_node_name);
  print('BreadthFirst: reply_func_node_name');
  for k,v in pairs(y) do print("\tNAME: " .. v); end

  print('BreadthFirst: rf_node_and_path {min=2; max=3;}');
  local z = traverse_bfs(V.lo2.node, rf_node_and_path,
                         {min_depth = 2;
                          max_depth = 3;});
  dump_node_and_path(z);

  print('DepthFirst: rf_node_and_path');
  z=traverse_dfs(V.lo2.node, rf_node_and_path);
  dump_node_and_path(z);

  print('DepthFirst: rf_path {min=2; max=3;}');
  x = traverse_dfs(V.lo2.node, rf_path,
                   {min_depth = 2;
                    max_depth = 3;});
  for k,v in pairs(x) do print("\tPATH: " .. v); end
end

local function getWeightProp(n)
  if (n['weight'] ~= nil) then return n['weight']; else return math.huge; end
end
function best_path_test()
  V = {};
  local tbl = 'cities';
  V.loA = {}; createNamedNode(tbl, V.loA, 11, 'A');
  V.loB = {}; createNamedNode(tbl, V.loB, 12, 'B');
  V.loC = {}; createNamedNode(tbl, V.loC, 14, 'C');
  V.loD = {}; createNamedNode(tbl, V.loD, 15, 'D');
  V.loE = {}; createNamedNode(tbl, V.loE, 16, 'E');
  V.loF = {}; createNamedNode(tbl, V.loF, 17, 'F');
  V.loG = {}; createNamedNode(tbl, V.loG, 18, 'G');
  V.loI = {}; createNamedNode(tbl, V.loI, 19, 'I');
  V.loJ = {}; createNamedNode(tbl, V.loJ, 20, 'J');
  V.loK = {}; createNamedNode(tbl, V.loK, 21, 'K');
  V.loL = {}; createNamedNode(tbl, V.loL, 22, 'L');
  V.loM = {}; createNamedNode(tbl, V.loM, 23, 'M');

  addNodeRelationShip(V.loA.node, 'PATH', V.loB.node);             -- cost: 100
  addPropertyToRelationship(V.loA.node, 'PATH', V.loB.node, 'weight', 100);

  addNodeRelationShip(V.loA.node, 'PATH', V.loC.node);             -- cost: 70
  addPropertyToRelationship(V.loA.node, 'PATH', V.loC.node, 'weight', 20);
  addNodeRelationShip(V.loC.node, 'PATH', V.loB.node);
  addPropertyToRelationship(V.loC.node, 'PATH', V.loB.node, 'weight', 50);

  addNodeRelationShip(V.loC.node, 'PATH', V.loD.node);             -- cost: 60
  addPropertyToRelationship(V.loC.node, 'PATH', V.loD.node, 'weight', 20);
  addNodeRelationShip(V.loD.node, 'PATH', V.loB.node);
  addPropertyToRelationship(V.loD.node, 'PATH', V.loB.node, 'weight', 20);

  addNodeRelationShip(V.loA.node, 'PATH', V.loE.node);             -- cost: 50
  addPropertyToRelationship(V.loA.node, 'PATH', V.loE.node, 'weight', 10);
  addNodeRelationShip(V.loE.node, 'PATH', V.loF.node);
  addPropertyToRelationship(V.loE.node, 'PATH', V.loF.node, 'weight', 10);
  addNodeRelationShip(V.loF.node, 'PATH', V.loB.node);
  addPropertyToRelationship(V.loF.node, 'PATH', V.loB.node, 'weight', 30);

  addNodeRelationShip(V.loF.node, 'PATH', V.loG.node);             -- cost: 40
  addPropertyToRelationship(V.loF.node, 'PATH', V.loG.node, 'weight', 10);
  addNodeRelationShip(V.loG.node, 'PATH', V.loB.node);
  addPropertyToRelationship(V.loG.node, 'PATH', V.loB.node, 'weight', 10);

  addNodeRelationShip(V.loA.node, 'PATH', V.loI.node);             -- cost: 30
  addPropertyToRelationship(V.loA.node, 'PATH', V.loI.node, 'weight', 5);
  addNodeRelationShip(V.loI.node, 'PATH', V.loJ.node);
  addPropertyToRelationship(V.loI.node, 'PATH', V.loJ.node, 'weight', 5);
  addNodeRelationShip(V.loJ.node, 'PATH', V.loK.node);
  addPropertyToRelationship(V.loJ.node, 'PATH', V.loK.node, 'weight', 5);
  addNodeRelationShip(V.loK.node, 'PATH', V.loL.node);
  addPropertyToRelationship(V.loK.node, 'PATH', V.loL.node, 'weight', 5);
  addNodeRelationShip(V.loL.node, 'PATH', V.loM.node);
  addPropertyToRelationship(V.loL.node, 'PATH', V.loM.node, 'weight', 5);
  addNodeRelationShip(V.loM.node, 'PATH', V.loB.node);
  addPropertyToRelationship(V.loM.node, 'PATH', V.loB.node, 'weight', 5);

  local t = shortestpath(V.loA.node, V.loB.node,
                         {relationship_cost_func = getWeightProp;});
  print('WEIGHT: shortestpath[A->B]: cost: ' .. t.cost ..  ' path: ' .. t.path);
end

function unique_none_test()
  V = {};
  V.loX = {}; createNamedNode(tbl, V.loX, 11, 'X');
  V.loY = {}; createNamedNode(tbl, V.loY, 12, 'Y');
  V.loZ = {}; createNamedNode(tbl, V.loZ, 14, 'Z');
  addNodeRelationShip(V.loX.node, 'KNOWS', V.loY.node);
  addNodeRelationShip(V.loY.node, 'KNOWS', V.loZ.node);
  addNodeRelationShip(V.loZ.node, 'KNOWS', V.loX.node);

  print('BreadthFirst: rf_node_and_path - UNIQ: NONE max_depth=10');
  local z = traverse_bfs(V.loX.node, rf_node_and_path,
                         {min_depth  = 1;
                          max_depth  = 10;
                          uniqueness = Uniqueness.NONE });
  dump_node_and_path(z);
end

function unique_path_test()
  V = {};
  V.loU = {}; createNamedNode(tbl, V.loU,  8, 'U');
  V.loV = {}; createNamedNode(tbl, V.loV,  9, 'V');
  V.loW = {}; createNamedNode(tbl, V.loW, 10, 'W');
  V.loX = {}; createNamedNode(tbl, V.loX, 11, 'X');
  V.loY = {}; createNamedNode(tbl, V.loY, 12, 'Y');
  V.loZ = {}; createNamedNode(tbl, V.loZ, 14, 'Z');
  addNodeRelationShip(V.loX.node, 'KNOWS', V.loY.node);
  addNodeRelationShip(V.loY.node, 'KNOWS', V.loZ.node);
  addNodeRelationShip(V.loZ.node, 'KNOWS', V.loX.node);

  addNodeRelationShip(V.loX.node, 'KNOWS', V.loW.node);
  addNodeRelationShip(V.loW.node, 'KNOWS', V.loZ.node);

  addNodeRelationShip(V.loW.node, 'KNOWS', V.loV.node);
  addNodeRelationShip(V.loV.node, 'KNOWS', V.loZ.node);

  addNodeRelationShip(V.loZ.node, 'KNOWS', V.loU.node);
  addNodeRelationShip(V.loU.node, 'KNOWS', V.loV.node);

  print('BreadthFirst: rf_node_and_path - UNIQ: PATH_GLOBAL');
  local z = traverse_bfs(V.loX.node, rf_node_and_path,
                         {uniqueness = Uniqueness.PATH_GLOBAL});
  dump_node_and_path(z);

  print('DepthFirst: rf_node_and_path - UNIQ: PATH_GLOBAL');
  z = traverse_dfs(V.loX.node, rf_node_and_path,
                    {uniqueness = Uniqueness.PATH_GLOBAL});
  dump_node_and_path(z);
end

-- GEOPATH GEOPATH GEOPATH GEOPATH GEOPATH GEOPATH GEOPATH GEOPATH GEOPATH
function getGeoDist(a, b)
  if (a == nil or a.x == nil or a.y == nil) then return math.huge; end
  if (b == nil or b.x == nil or b.y == nil) then return math.huge; end
  local dx = a.x - b.x; local dy = a.y - b.y;
  return math.sqrt((dx * dx) + (dy * dy));
end
function best_geopath_test()
  V = {};
  local tbl = 'geospots';
  V.loA = {}; createNamedNode(tbl, V.loA, 110, 'A');
  addNodeProperty(V.loA.node, 'x',   0); addNodeProperty(V.loA.node, 'y', 0);
  V.loB = {}; createNamedNode(tbl, V.loB, 120, 'B');
  addNodeProperty(V.loB.node, 'x', 100); addNodeProperty(V.loB.node, 'y', 100);
  V.loC = {}; createNamedNode(tbl, V.loC, 130, 'C');
  addNodeProperty(V.loC.node, 'x',   0); addNodeProperty(V.loC.node, 'y', 100);
  V.loD = {}; createNamedNode(tbl, V.loD, 140, 'D');
  addNodeProperty(V.loD.node, 'x', 100); addNodeProperty(V.loD.node, 'y',   0);
  V.loE = {}; createNamedNode(tbl, V.loE, 150, 'E');
  addNodeProperty(V.loE.node, 'x',  75); addNodeProperty(V.loE.node, 'y',  25);
  V.loF = {}; createNamedNode(tbl, V.loF, 160, 'F');
  addNodeProperty(V.loF.node, 'x',  25); addNodeProperty(V.loF.node, 'y',  75);
  V.loG = {}; createNamedNode(tbl, V.loG, 170, 'G');
  addNodeProperty(V.loG.node, 'x',  25); addNodeProperty(V.loG.node, 'y',  25);
  V.loH = {}; createNamedNode(tbl, V.loH, 180, 'H');
  addNodeProperty(V.loH.node, 'x',  75); addNodeProperty(V.loH.node, 'y',  75);

  addNodeRelationShip(V.loA.node, 'PATH', V.loC.node); -- A->C->B
  addNodeRelationShip(V.loC.node, 'PATH', V.loB.node);

  addNodeRelationShip(V.loA.node, 'PATH', V.loD.node); -- A->D->B
  addNodeRelationShip(V.loD.node, 'PATH', V.loB.node);

  addNodeRelationShip(V.loA.node, 'PATH', V.loE.node); -- A->E->B
  addNodeRelationShip(V.loE.node, 'PATH', V.loB.node);

  addNodeRelationShip(V.loA.node, 'PATH', V.loF.node); -- A->F->B
  addNodeRelationShip(V.loF.node, 'PATH', V.loB.node);

  addNodeRelationShip(V.loA.node, 'PATH', V.loG.node); -- A->G->H->B
  addNodeRelationShip(V.loG.node, 'PATH', V.loH.node);
  addNodeRelationShip(V.loH.node, 'PATH', V.loB.node);

  local t = shortestpath(V.loA.node, V.loB.node,
                        {node_diff_func = getGeoDist;});
  print('DISTANCE: shortestpath[A->B]: cost: ' .. t.cost ..
                                     ' path: ' .. t.path);
end

-- FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF FOF
-- EDGE_EVAL (used in ALL FOF tests)
local function fof_edge_eval(x)
  if     (x.depth <  4) then return Evaluation.EXCLUDE_AND_CONTINUE;
  elseif (x.depth == 4) then return Evaluation.INCLUDE_AND_CONTINUE;
  else                       return Evaluation.INCLUDE_AND_PRUNE; end
end

-- EXPANDER
local function fof_expander(x, rtype, relation)
  local ok;
  if     (x.depth < 3) then
    ok = ((rtype == 'KNOWS')      and (relation[Direction.OUTGOING] ~= nil));
  else
    ok = false;
    if ((rtype == 'VIEWED_PIC') and (relation[Direction.OUTGOING] ~= nil)) then
      local pk;
      for k, v in pairs(relation[Direction.OUTGOING]) do pk = k; end
      if (pk == StartPK) then ok = true; end
    end
  end
  return ok, Direction.OUTGOING;
end

-- EXPANDER
-- Examines ALL relationships a NODE has and returns relations to be expanded
local function fof_all_rel_expander(x, relations)
  local knows_out  = {};
  local viewed_out = {};
  local do_us      = {};
  for rtype, relation in pairs(relations) do
    if (relation[Direction.OUTGOING] ~= nil) then
      if (rtype == 'KNOWS')      then
          if (viewed_out[x.w.node.__pk] ~= nil) then
            table.insert(do_us,
                         {rtype = 'VIEWED_PIC';
                          relation = viewed_out[x.w.node.__pk]});
          else
            table.insert(knows_out, x.w.node.__pk, relation);
          end
      end
      if (rtype == 'VIEWED_PIC') then
          if (knows_out[x.w.node.__pk] ~= nil) then
            table.insert(do_us, {rtype = rtype; relation = relation}); -- HIT
          else
            table.insert(viewed_out, x.w.node.__pk, relation);
          end
      end
    end
  end
  return do_us;
end
function fof_complicated_test()
  V = {};
  local tbl = 'friends';
  V.loA = {}; createNamedNode(tbl, V.loA, 110, 'A');
  V.loB = {}; createNamedNode(tbl, V.loB, 120, 'B');
  V.loC = {}; createNamedNode(tbl, V.loC, 130, 'C');
  V.loD = {}; createNamedNode(tbl, V.loD, 140, 'D');
  V.loE = {}; createNamedNode(tbl, V.loE, 150, 'E');
  V.loF = {}; createNamedNode(tbl, V.loF, 160, 'F');
  V.loG = {}; createNamedNode(tbl, V.loG, 170, 'G');
  addNodeRelationShip(V.loA.node, 'KNOWS', V.loB.node);
  addNodeRelationShip(V.loB.node, 'KNOWS', V.loD.node);
  addNodeRelationShip(V.loD.node, 'KNOWS', V.loG.node);
  addNodeRelationShip(V.loA.node, 'KNOWS', V.loC.node);
  addNodeRelationShip(V.loC.node, 'KNOWS', V.loE.node);
  addNodeRelationShip(V.loC.node, 'KNOWS', V.loF.node);

  addNodeRelationShip(V.loA.node, 'VIEWED_PIC', V.loB.node);
  addNodeRelationShip(V.loB.node, 'VIEWED_PIC', V.loD.node);
  addNodeRelationShip(V.loD.node, 'VIEWED_PIC', V.loA.node);

  addNodeRelationShip(V.loF.node, 'VIEWED_PIC', V.loA.node);

  addNodeRelationShip(V.loE.node, 'VIEWED_PIC', V.loG.node);

  print('FOF who have seen my picture');
  local z = traverse_bfs(V.loA.node, rf_node_and_path, 
                         {uniqueness     = Uniqueness.PATH_GLOBAL;
                          edge_eval_func = fof_edge_eval;
                          expander_func  = fof_expander;});
  dump_node_and_path(z);

  print('FriendsANDPictureSeen-OfFriends  who have seen my picture');
  z = traverse_bfs(V.loA.node, rf_node_and_path, 
                   {uniqueness            = Uniqueness.PATH_GLOBAL;
                    edge_eval_func        = fof_edge_eval;
                    all_rel_expander_func = fof_all_rel_expander;});
  dump_node_and_path(z);

  print('DepthFirst: FOF who have seen my picture');
  z = traverse_dfs(V.loA.node, rf_node_and_path, 
                   {uniqueness     = Uniqueness.PATH_GLOBAL;
                    edge_eval_func = fof_edge_eval;
                    expander_func  = fof_expander;});
  dump_node_and_path(z);
end

-- BOTH_DIRECTIONS BOTH_DIRECTIONS BOTH_DIRECTIONS BOTH_DIRECTIONS
local function both_directions_expander(x, rtype, relation)
  return true, Direction.BOTH;
end
function both_direction_test()
  V.loA = {}; createNamedNode(tbl, V.loA, 110, 'A');
  V.loB = {}; createNamedNode(tbl, V.loB, 120, 'B');
  V.loC = {}; createNamedNode(tbl, V.loC, 130, 'C');
  addNodeRelationShip(V.loA.node, 'KNOWS', V.loB.node);
  addNodeRelationShip(V.loC.node, 'KNOWS', V.loB.node);

  print('both directions test A->B<-C');
  local z = traverse_bfs(V.loA.node, rf_node_and_path, 
                         {expander_func = both_directions_expander;});
  dump_node_and_path(z);
end

function run_tests()
  initial_test();
  best_path_test();
  unique_none_test();
  unique_path_test();
  best_geopath_test();
  fof_complicated_test();
  both_direction_test();
end
