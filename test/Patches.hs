{-# LANGUAGE TemplateHaskell #-}

module Patches where

import Test.Framework
import Test.Framework.TH
import Test.HUnit
import Test.Framework.Providers.HUnit

patchesTestGroup = $(testGroupGenerator)
case_1 = do 1 @=? 1
case_2 = do 2 @=? 2
case_3 = do 3 @=? 3