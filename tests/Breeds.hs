{-# LANGUAGE TemplateHaskell #-}

module Breeds (breedsTestGroup) where

import Test.Tasty
import Test.Tasty.HUnit
import Utility

import Language.Logo
import Control.Monad.Trans.Class (lift)

globals ["glob1"]
breeds ["frogs", "frog"]
breeds ["mice", "mouse"]
breeds_own "frogs" []
breeds_own "mice" []
run [] -- workaround for tests

breedsTestGroup =
 [testCase "case_TestIsBreed" $ runT $ do
    a1 <- atomic $ is_frogp =<< nobody
    let e1 = False
    lift $ e1 @=? a1

    a2 <- atomic $ is_frogp =<< turtle 0
    let e2 = False
    lift $ e2 @=? a2

    create_turtles 1

    a3 <- atomic $ is_frogp =<< turtle 0
    let e3 = False
    lift $ e3 @=? a3
  
    create_frogs 1

    a4 <- atomic $ is_frogp =<< turtle 1
    let e4 = True
    lift $ e4 @=? a4

    a5 <- atomic $ is_mousep =<< turtle 1
    let e5 = False
    lift $ e5 @=? a5

    ask (atomic $ die) =<< turtle 1
  
    a6 <- atomic $ is_frogp =<< turtle 1
    let e6 = False
    lift $ e6 @=? a6

    a7 <- atomic $ is_mousep =<< turtle 1
    let e7 = False
    lift $ e7@=? a7


 ,testCase "case_IsLinkBreed" $ runT $ do
    a1 <- atomic $ is_directed_linkp =<< nobody
    let e1 = False
    lift $ e1 @=? a1

    a2 <- atomic $ is_directed_linkp =<< link 0 1
    let e2 = False
    lift $ e2 @=? a2

    crt 2
    ask (atomic $ create_link_to =<< turtle 1) =<< turtle 0

    a3 <- atomic $ is_directed_linkp =<< link 0 1
    let e3 = True
    lift $ e3 @=? a3

  
 ,testCase "case_SetBreedToNonBreed" $ runT $ do
    crt 1
    ask (atomic $ set_breed "turtles") =<< turtle 0

    crt 1
    ask (atomic $ set_breed "frogs") =<< turtle 1

    crt 1
    ask (atomic $ set_breed "patches") =<< turtle 2
                                         
    crt 1
    ask (atomic $ set_breed "links") =<< turtle 3

    lift $ assertFailure "No run-time checking of the breed type and value on setting"
 ]
