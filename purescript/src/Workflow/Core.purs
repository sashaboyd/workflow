module Workflow.Core where

import Control.Monad.Except.Trans (ExceptT)
import Data.Array (filter, mapMaybe, (!!), zipWith)
import Data.Eq (class Eq)
import Data.Foldable (elem, foldl)
import Data.Generic.Rep (class Generic)
import Data.Identity (Identity)
import Data.Lens (Lens', lens, view, over, set, setJust)
import Data.Lens.At (at)
import Data.Lens.Record (prop)
import Data.List (List(..), (:))
import Data.List.NonEmpty (NonEmptyList)
import Data.Maybe (Maybe(..))
import Data.Maybe as Maybe
import Data.String (Pattern(..), contains, stripPrefix, trim)
import Data.Symbol (SProxy(..))
import Data.Tuple (Tuple(..))
import Data.UUID (genUUID)
import Effect (Effect)
import Foreign (ForeignError)
import Foreign.Class (class Encode, class Decode)
import Foreign.Generic (defaultOptions, genericEncode, genericDecode, genericDecodeJSON, genericEncodeJSON)
import Foreign.Generic.Types (SumEncoding)
import Foreign.Object (Object, keys, values, fromFoldable)
import Foreign.Object as Object
import Prelude (Unit, unit, ($), (<<<), map, flip, (<>), bind, pure, (>>=), (+), (<$>), (-), show)

version :: String
version = "0.001"

-- TODO: move these constants to UI
newNodeXOffset :: Number
newNodeXOffset = 100.0

newNodeYOffset :: Number
newNodeYOffset = 100.0

newNodeInitialPos :: Point2D
newNodeInitialPos = { x: 100.0, y: 100.0 }

genericEncodeOpts ::
  { unwrapSingleConstructors :: Boolean
  , fieldTransform :: String -> String
  , sumEncoding :: SumEncoding
  , unwrapSingleArguments :: Boolean
  }
genericEncodeOpts = defaultOptions { unwrapSingleConstructors = true }

type NodeId = String

type NodeIdSet = Object Unit

insert :: NodeId -> NodeIdSet -> NodeIdSet
insert nodeId = Object.insert nodeId unit

delete :: NodeId -> NodeIdSet -> NodeIdSet
delete = Object.delete

nodeIdSetFromArray :: Array NodeId -> NodeIdSet
nodeIdSetFromArray nodeIdArr = Object.fromFoldable $ map (\nodeId -> (Tuple nodeId unit)) nodeIdArr

emptyNodeIdSet :: NodeIdSet
emptyNodeIdSet = Object.empty


class BasicGraph where
  createNode :: Point2D -> NodeIdSet -> NodeIdSet -> Effect GraphNode
  insertNode :: GraphNode -> Graph -> Graph
  removeNode :: NodeId -> Graph -> Graph
  addEdge :: Edge -> Graph -> Graph
  removeEdge :: Edge -> Graph -> Graph
  glue :: Graph -> Graph -> Graph
  unglue :: Array GraphNode -> Graph -> { parentGraph :: Graph, childGraph :: Graph }

instance graphOps :: BasicGraph where
  createNode = createGraphNode
  insertNode = insertNodeImpl
  removeNode = removeNodeImpl
  addEdge = addEdgeImpl
  removeEdge = removeEdgeImpl
  glue = glueImpl
  unglue = unglueImpl

newtype Graph = Graph
  { nodes :: Object GraphNode
  , focus :: Focus
  , highlighted :: NodeIdSet
  }
derive instance genericGraph :: Generic Graph _

instance encodeGraph :: Encode Graph where
  encode = genericEncode genericEncodeOpts

instance decodeGraph :: Decode Graph where
  decode = genericDecode genericEncodeOpts

graphToJSON :: Graph -> String
graphToJSON g =
  genericEncodeJSON genericEncodeOpts g

graphFromJSON :: String -> ExceptT (NonEmptyList ForeignError) Identity Graph
graphFromJSON graphJSON = genericDecodeJSON genericEncodeOpts graphJSON

emptyGraph :: Graph
emptyGraph = Graph
  { nodes: Object.empty
  , focus: NoFocus
  , highlighted: emptyNodeIdSet
  }

newtype GraphNode = GraphNode
  { text :: String
  , valid :: Boolean
  , id :: NodeId
  , x :: Number
  , y :: Number
  , children :: NodeIdSet
  , parents :: NodeIdSet
  , subgraphNodes :: Object GraphNode
  }
derive instance genericGraphNode :: Generic GraphNode _
derive instance eqGraphNode :: Eq GraphNode

instance encodeGraphNode :: Encode GraphNode where
  encode node = genericEncode genericEncodeOpts node

instance decodeGraphNode :: Decode GraphNode where
  decode node = genericDecode genericEncodeOpts node

type Point2D = { x :: Number, y :: Number }

add :: Point2D -> Point2D -> Point2D
add a b = {x: a.x + b.x, y: a.y + b.y}

subtract :: Point2D -> Point2D -> Point2D
subtract a b = {x: a.x - b.x, y: a.y - b.y}

createGraphNode :: Point2D -> NodeIdSet -> NodeIdSet -> Effect GraphNode
createGraphNode xyPos parentIds childIds = do
   nodeId <- genUUID
   pure $ GraphNode
      { text : ""
      , valid : true
      , id : show nodeId
      , x : xyPos.x
      , y : xyPos.y
      , children : childIds
      , parents : parentIds
      , subgraphNodes : Object.empty
      }

newtype Edge = Edge { source :: NodeId, target :: NodeId }
derive instance genericEdge :: Generic Edge _
derive instance eqEdge :: Eq Edge
instance encodeEdge :: Encode Edge where
  encode x = genericEncode genericEncodeOpts x
instance decodeEdge :: Decode Edge where
  decode x = genericDecode genericEncodeOpts x

type EdgeId = String

computeEdgeId :: Edge -> String
computeEdgeId (Edge edge) = edge.source <> "." <> edge.target

-- | Utility
edgesToFromNode :: GraphNode -> Array Edge
edgesToFromNode (GraphNode node) =
  let
    edgesToChildren = map (
      \childNodeId -> Edge { source : node.id
                           , target : childNodeId }
      ) $ keys node.children
    edgesFromParents = map (
      \parentNodeId -> Edge { source : parentNodeId
                            , target : node.id }
      ) $ keys node.parents
  in
    edgesToChildren <> edgesFromParents

resolveEdgeNodes :: Edge -> Graph -> Maybe { source :: GraphNode, target :: GraphNode }
resolveEdgeNodes (Edge edge) g = do
  source <- lookupNode g edge.source
  target <- lookupNode g edge.target
  pure { source : source, target : target }

graphEdges :: Graph -> Array Edge
graphEdges (Graph g) = do
  GraphNode node <- values g.nodes
  childId <- keys node.children
  pure $ Edge { source : node.id, target : childId }

data Focus =
  FocusNode String
  | FocusEdge Edge (Array Edge)
  | NoFocus
derive instance genericFocus :: Generic Focus _
derive instance eqFocus :: Eq Focus

instance encodeFocus :: Encode Focus where
  encode x = genericEncode genericEncodeOpts x

instance decodeFocus :: Decode Focus where
  decode x = genericDecode genericEncodeOpts x


data GraphOp =
  AddNode GraphNode
  | RemoveNode GraphNode
  | MoveNode NodeId Point2D
  | AddParent NodeId NodeId
  | RemoveParent NodeId NodeId
  | AddChild NodeId NodeId
  | RemoveChild NodeId NodeId
  | AddEdge Edge
  | RemoveEdge Edge
  | UpdateText NodeId String
  | UpdateSubgraphNodes NodeId (Object GraphNode)
  | UpdateFocus Focus
  | Highlight NodeId
  | UnHighlight NodeId
  | UpdateNodeValidity NodeId Boolean

------
-- Lens boilerplate

_Graph :: Lens' Graph { nodes :: Object GraphNode
                      ,  focus :: Focus
                      ,  highlighted :: NodeIdSet}
_Graph = lens (\(Graph g) -> g) (\_ -> Graph)

_nodes :: forall r. Lens' { nodes :: Object GraphNode | r } (Object GraphNode)
_nodes = prop (SProxy :: SProxy "nodes")

_highlighted :: forall r. Lens' { highlighted :: NodeIdSet | r } NodeIdSet
_highlighted = prop (SProxy :: SProxy "highlighted")

_GraphNode :: Lens' GraphNode { text :: String
                              , valid :: Boolean
                              , id :: NodeId
                              , x :: Number
                              , y :: Number
                              , children :: NodeIdSet
                              , parents :: NodeIdSet
                              , subgraphNodes :: Object GraphNode
                              }
_GraphNode = lens (\(GraphNode n) -> n) (\_ -> GraphNode)

_parents :: forall r. Lens' { parents :: NodeIdSet | r } NodeIdSet
_parents = prop (SProxy :: SProxy "parents")

_children :: forall r. Lens' { children :: NodeIdSet | r } NodeIdSet
_children = prop (SProxy :: SProxy "children")

_x :: forall r. Lens' { x :: Number | r } Number
_x = prop (SProxy :: SProxy "x")

viewX :: GraphNode -> Number
viewX = view (_GraphNode <<< _x)

_y :: forall r. Lens' { y :: Number | r } Number
_y = prop (SProxy :: SProxy "y")

_text :: forall r. Lens' { text :: String | r } String
_text = prop (SProxy :: SProxy "text")

_valid :: forall r. Lens' { valid :: Boolean | r } Boolean
_valid = prop (SProxy :: SProxy "valid")

_id :: forall r. Lens' { id :: String | r } String
_id = prop (SProxy :: SProxy "id")

_subgraphNodes :: forall r. Lens' { subgraphNodes :: Object GraphNode | r } (Object GraphNode)
_subgraphNodes = prop (SProxy :: SProxy "subgraphNodes")

_focus :: forall r. Lens' { focus :: Focus | r } Focus
_focus = prop (SProxy :: SProxy "focus")


------
-- Graph logic

addParent :: NodeId -> GraphNode -> GraphNode
addParent nodeId = over (_GraphNode <<< _parents) $ insert nodeId

deleteParent :: NodeId -> GraphNode -> GraphNode
deleteParent nodeId = over (_GraphNode <<< _parents) $ delete nodeId

addChild :: NodeId -> GraphNode -> GraphNode
addChild nodeId = over (_GraphNode <<< _children) $ insert nodeId

deleteChild :: NodeId -> GraphNode -> GraphNode
deleteChild nodeId = over (_GraphNode <<< _children) $ delete nodeId

moveNode :: Point2D -> GraphNode -> GraphNode
moveNode pos = set (_GraphNode <<< _x) pos.x <<<
               set (_GraphNode <<< _y) pos.y

updateText :: String -> GraphNode -> GraphNode
updateText = set (_GraphNode <<< _text)

replaceSubgraphNodes :: Object GraphNode -> GraphNode -> GraphNode
replaceSubgraphNodes = set (_GraphNode <<< _subgraphNodes)

-- TODO: replace GraphOp with bag-of-functions
applyGraphOp :: GraphOp -> Graph -> Graph
applyGraphOp (AddNode (GraphNode nodeBody)) =
  setJust (_Graph <<< _nodes <<< (at nodeBody.id)) (GraphNode nodeBody)
applyGraphOp (RemoveNode (GraphNode nodeBody)) =
  set (_Graph <<< _nodes <<< (at nodeBody.id)) Nothing
applyGraphOp (MoveNode nodeId pos) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ moveNode pos
applyGraphOp (AddParent nodeId parentId) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ addParent parentId
applyGraphOp (RemoveParent nodeId parentId) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ deleteParent parentId
applyGraphOp (AddChild nodeId childId) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ addChild childId
applyGraphOp (RemoveChild nodeId childId) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ deleteChild childId
applyGraphOp (AddEdge (Edge edge)) =
  applyGraphOp (AddParent edge.target edge.source)
  <<<
  applyGraphOp (AddChild edge.source edge.target)
applyGraphOp (RemoveEdge (Edge edge)) =
  applyGraphOp (RemoveParent edge.target edge.source)
  <<<
  applyGraphOp (RemoveChild edge.source edge.target)
applyGraphOp (UpdateText nodeId newText) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ updateText newText
applyGraphOp (UpdateSubgraphNodes nodeId newSubgraphNodes) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ replaceSubgraphNodes newSubgraphNodes
applyGraphOp (UpdateFocus newFocus) =
  over _Graph (_ { focus = newFocus})
applyGraphOp (Highlight nodeId) =
  over (_Graph <<< _highlighted) (insert nodeId)
applyGraphOp (UnHighlight nodeId) =
  over (_Graph <<< _highlighted) (delete nodeId)
applyGraphOp (UpdateNodeValidity nodeId validity) =
  over (_Graph <<< _nodes <<< (at nodeId)) $ map $ set (_GraphNode <<< _valid) validity

insertNodeImpl :: GraphNode -> Graph -> Graph
insertNodeImpl newNode g =
  let
    newNodeId = (view (_GraphNode <<< _id) newNode)
    addParentEdges = map (\parentId -> AddChild parentId newNodeId) $ keys $ view (_GraphNode <<< _parents) newNode
    addChildEdges = map (\childId -> AddParent childId newNodeId) $ keys $ view (_GraphNode <<< _children) newNode
  in
    foldl (flip applyGraphOp) g
      $ [AddNode newNode] <> addParentEdges <> addChildEdges
      <> [UpdateFocus (FocusNode newNodeId)]

-- TODO: add to interface typeclass.
removeNodeImpl :: NodeId -> Graph -> Graph
removeNodeImpl nodeId g = case lookupNode g nodeId of
  Nothing -> g
  Just (GraphNode node) ->
    applyGraphOp (RemoveNode (GraphNode node))
    $ removeParents node.id
    $ removeChildren node.id
    $ g

removeParents :: NodeId -> Graph -> Graph
removeParents nodeId g =
  case lookupNode g nodeId of
    Nothing -> g
    Just (GraphNode node) ->
      foldl (\graph parentId ->
              (removeEdge (Edge { source : parentId, target : nodeId }) graph))
        g
        $ keys node.parents

removeChildren :: NodeId -> Graph -> Graph
removeChildren nodeId g =
  case lookupNode g nodeId of
    Nothing -> g
    Just (GraphNode node) ->
      foldl (\graph childId ->
              (removeEdge (Edge { source : nodeId, target : childId }) graph))
        g
        $ keys node.children

replaceParents :: NodeIdSet -> NodeId -> Graph -> Graph
replaceParents newParents nodeId g =
  foldl (\graph parentId ->
          addEdge (Edge { source : parentId, target : nodeId }) graph)
    (removeParents nodeId g)
    (keys newParents)

replaceChildren :: NodeIdSet -> NodeId -> Graph -> Graph
replaceChildren newChildren nodeId g =
  foldl (\graph childId ->
          addEdge (Edge { source : nodeId, target : childId }) graph)
    (removeChildren nodeId g)
    (keys newChildren)

updateNodePosition :: Point2D -> NodeId -> Graph -> Graph
updateNodePosition newPos nodeId = applyGraphOp (MoveNode nodeId newPos)

-- TODO: add to interface typeclass.
addEdgeImpl :: Edge -> Graph -> Graph
addEdgeImpl edge g = applyGraphOp (AddEdge edge) g

-- TODO: add to interface typeclass.
removeEdgeImpl :: Edge -> Graph -> Graph
removeEdgeImpl edge g = applyGraphOp (RemoveEdge edge) g

moveNodeAmount :: Point2D -> GraphNode -> Graph -> Graph
moveNodeAmount motion (GraphNode node) g =
   let newPos = add {x: node.x, y: node.y} motion in
   applyGraphOp (MoveNode node.id newPos) g

highlight :: NodeId -> Graph -> Graph
highlight nodeId g = applyGraphOp (Highlight nodeId) g

unHighlight :: NodeId -> Graph -> Graph
unHighlight nodeId g = applyGraphOp (UnHighlight nodeId) g

clearHighlighted :: Graph -> Graph
clearHighlighted = set (_Graph <<< _highlighted) emptyNodeIdSet

updateNodeText :: String -> NodeId -> Graph -> Graph
updateNodeText newText nodeId = applyGraphOp (UpdateText nodeId newText)

-- | Take a child graph that has edges to a parent graph that are not
-- | mirrored, add the matching edges from parent graph to child graph
-- | and merge the node sets.
-- | This is used to merge a collapsed subgraph back into the main graph,
-- | and will also support breaking down and joining graphs for filtering
-- | and composing semantic networks or something :D
-- TODO: add to interface typeclass
glueImpl :: Graph -> Graph -> Graph
glueImpl childGraph parentGraph =
  let
    childGraphNodeArray = values $ view (_Graph <<< _nodes) childGraph
    childGraphEdges = do
      childGraphNode <- childGraphNodeArray
      edgesToFromNode childGraphNode
    allNodes = foldl (flip insertNode) parentGraph childGraphNodeArray
    childGraphNodeIds = nodeIdSetFromArray $ map (view (_GraphNode <<< _id)) childGraphNodeArray
    mergedGraph = Graph { nodes : view (_Graph <<< _nodes) allNodes
                        , focus : view (_Graph <<< _focus) childGraph
                        , highlighted : childGraphNodeIds
                        }
  in
    foldl (flip addEdge) mergedGraph childGraphEdges

-- | Almost-inverse of glue (modulo some type conversions)
unglueImpl :: Array GraphNode -> Graph -> { parentGraph :: Graph, childGraph :: Graph }
unglueImpl childGraphNodes g =
  let
    childGraphNodeIds = map (view (_GraphNode <<< _id)) childGraphNodes
    childGraphEdges = do
      childGraphNode <- childGraphNodes
      edgesToFromNode childGraphNode
    ungluedParentGraph = foldl (flip removeNode) g childGraphNodeIds
    parentGraph = foldl (flip removeEdge) ungluedParentGraph childGraphEdges
    childGraphNodeSet = zipWith Tuple childGraphNodeIds childGraphNodes
    childGraph = Graph { nodes : fromFoldable childGraphNodeSet
                       , focus : NoFocus
                       , highlighted : Object.empty
                       }
  in
    { parentGraph : parentGraph
    , childGraph : childGraph
    }


demo :: Graph
demo = foldl (flip applyGraphOp) emptyGraph $
       UpdateFocus (FocusEdge (Edge { source: "title"
                                    , target: "goofus"})
                              [Edge {"source": "title", "target": "goofus"},
                               Edge {"source": "thingo", "target": "goofus"}])
       : AddNode (GraphNode
           { text: "Title: Workflow"
           , valid: true
           , id : "title"
           , x : 205.0
           , y : 150.0
           , parents : emptyNodeIdSet
           , children : nodeIdSetFromArray ["goofus"]
           , subgraphNodes : Object.empty
           })
       : Highlight "thingo"
       : AddNode (GraphNode
           { text: "thingo"
           , valid: false
           , id : "thingo"
           , x : 205.0
           , y : 100.0
           , parents : emptyNodeIdSet
           , children : nodeIdSetFromArray ["goofus"]
           , subgraphNodes : Object.empty
           })
       : AddNode (GraphNode
           { text: "asdf"
           , valid: true
           , id : "goofus"
           , x: 450.0
           , y: 270.0
           , parents : nodeIdSetFromArray [ "thingo", "title" ]
           , children : emptyNodeIdSet
           , subgraphNodes : Object.empty
           })
       : Nil


------
-- Utilities

lookupNode :: Graph -> NodeId -> Maybe GraphNode
lookupNode g nodeId = view (_Graph <<< _nodes <<< at nodeId) g

lookupNodes :: Graph -> NodeIdSet -> Array GraphNode
lookupNodes g nodeIds = mapMaybe (lookupNode g) $ keys nodeIds

resolvedGraphEdges :: Graph -> Array { source :: GraphNode, target :: GraphNode }
resolvedGraphEdges g =
  mapMaybe (flip resolveEdgeNodes g) $ graphEdges g

------
-- Graph Queries

-- TODO: re-export to JS using module system properly
fromMaybe :: forall a. a -> Maybe a -> a
fromMaybe = Maybe.fromMaybe

maybe :: forall a. a -> Maybe a
maybe = Just

fromFocus :: Focus -> String
fromFocus NoFocus = ""
fromFocus (FocusNode nodeId) = nodeId
fromFocus (FocusEdge edge _) = computeEdgeId edge

edgeInFocusGroup :: Graph -> Edge -> Boolean
edgeInFocusGroup (Graph g) edge =
  case g.focus of
    FocusEdge _ focusGroup -> elem edge focusGroup
    _ -> false

getParents :: GraphNode -> NodeIdSet
getParents (GraphNode node) = node.parents

getChildren :: GraphNode -> NodeIdSet
getChildren (GraphNode node) = node.children

graphTitle :: Graph -> Maybe String
graphTitle (Graph g) = titles !! 0 >>= stripPrefix titlePattern
  where
    titlePattern = Pattern "Title: "
    nodeTextArr = trim <$> (view (_GraphNode <<< _text)) <$> values g.nodes
    isTitle = contains titlePattern
    titles = filter isTitle nodeTextArr