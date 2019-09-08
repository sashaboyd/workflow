module DemoGraph where

import Prelude
import Effect (Effect)

import Data.Map as Map
import Data.Set as Set

import Data.Lens ((%~), (.~))

import Data.UUID (genUUID)

import Workflow.UIGraph.Types (UIGraph, UINode(..), UIEdge(..), Focus(..), _highlighted, _focus)
import Workflow.UIGraph (emptyUIGraph)
import Workflow.Core (insertNode, insertEdge)

demo :: Effect UIGraph
demo = do
  oscillatorId <- genUUID
  delayId <- genUUID
  amplifierId <- genUUID
  outputId <- genUUID
  filterId <- genUUID
  pure $
    emptyUIGraph
    # insertNode (UINode { text: "oscillator"
                         , isValid: true
                         , position : { x: 450.0
                                      , y: 270.0
                                      }
                         , id : oscillatorId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertNode (UINode { text: "delay"
                         , isValid: true
                         , position : { x: 450.0
                                      , y: 170.0
                                      }
                         , id : delayId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertNode (UINode { text: "gain"
                         , isValid: true
                         , position : { x: 650.0
                                      , y: 270.0
                                      }
                         , id : amplifierId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertNode (UINode { text: "output"
                         , isValid: true
                         , position : { x: 800.0
                                      , y: 270.0
                                      }
                         , id : outputId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertNode (UINode { text: "analyser"
                         , isValid: true
                         , position : { x: 550.0
                                      , y: 370.0
                                      }
                         , id : filterId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertEdge (UIEdge  { id : { source : oscillatorId
                                 , target : delayId
                                 }
                          , text : ""
                          , isValid : false
                          })
    # insertEdge (UIEdge  { id : { source : delayId
                                 , target : amplifierId
                                 }
                          , text : ""
                          , isValid : false
                          })
    # insertEdge (UIEdge  { id : { source : amplifierId
                                 , target : outputId
                                 }
                          , text : ""
                          , isValid : false
                          })
    # insertEdge (UIEdge  { id : { source : amplifierId
                                 , target : filterId
                                 }
                          , text : ""
                          , isValid : false
                          })

demo_ :: Effect UIGraph
demo_ = do
  goofusId <- genUUID
  thingoId <- genUUID
  titleId <- genUUID
  pure $
    emptyUIGraph
    # insertNode (UINode { text: "asdfasdfasdfasdf"
                         , isValid: true
                         , position : { x: 450.0
                                      , y: 270.0
                                      }
                         , id : goofusId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertNode (UINode { text: ""
                         , isValid: true
                         , position : { x : 205.0
                                      , y : 100.0
                                      }
                         , id : thingoId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertNode (UINode { text: "Title: Workflow"
                         , isValid: true
                         , position : { x : 205.0
                                      , y : 150.0
                                      }
                         , id : titleId
                         , parents : Map.empty
                         , children : Map.empty
                         , subgraph : emptyUIGraph
                         })
    # insertEdge (UIEdge { id : { source : thingoId
                                , target : goofusId
                                }
                         , text : ""
                         , isValid : false
                         })
    # insertEdge (UIEdge  { id : { source : titleId
                                 , target : goofusId
                                 }
                          , text : "hehehe"
                          , isValid : false
                          })
    # _highlighted %~ Set.insert thingoId
    # _focus .~ (FocusEdge { source: titleId
                           , target: goofusId
                           }
                 [{ source: titleId
                  , target: goofusId
                  },
                  { source: thingoId
                  , target: goofusId
                  }
                 ]
                )
