-- |
-- Module      : Presentation.Yeamer.Internal.Progress
-- Copyright   : (c) Justus Sagemüller 2018
-- License     : GPL v3
-- 
-- Maintainer  : (@) jsag $ hvl.no
-- Stability   : experimental
-- Portability : portable
-- 
{-# LANGUAGE DeriveGeneric              #-}
module Presentation.Yeamer.Internal.Progress where


import Presentation.Yeamer.Internal.PrPathStepCompression

import Data.Map (Map)
import qualified Data.Map as Map
import qualified Data.Vector as Arr

import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as BSL
import Data.Text (Text)
import qualified Data.Text.Encoding as Txt
import qualified Data.ByteString.Base64.URL as URLBase64

import Flat (Flat, flat, unflat)
import qualified Flat.Class as Flat
import qualified Data.Aeson as JSON

import Yesod (PathPiece(..))

import Control.Arrow ((>>>), (<<<))
import Control.Monad ((>=>))
import Control.Monad.Trans.List
import Control.Monad.Trans.Writer
import Lens.Micro (_Right)
import Lens.Micro.Extras (preview)

import Data.Traversable.Redundancy (rmRedundancy)

import GHC.Generics


type PrPath = Text

newtype PresProgress = PresProgress
    { getPresentationProgress :: Map [PrPath] ByteString }
    deriving (Eq, Show, Read)

instance PathPiece PresProgress where
  fromPathPiece = Txt.encodeUtf8
              >>> preview _Right . URLBase64.decode
              >=> preview _Right . fmap assemblePresProgress . unflat
  toPathPiece   = Txt.decodeUtf8
              <<<                  URLBase64.encode
              <<<                  flat . disassemblePresProgress

assemblePresProgress :: ((ByteString, [ByteString]), Map [Int] Int) -> PresProgress
assemblePresProgress ((pSR_l_c, pKR_l), prog_c)
          = PresProgress . Map.mapKeys (map (progStepRsr Arr.!))
                          $ fmap (progKeyRsr Arr.!) prog_c
 where progStepRsr = Arr.fromList $ decompressPrPathSteps pSR_l_c
       progKeyRsr = Arr.fromList pKR_l

disassemblePresProgress :: PresProgress -> ((ByteString, [ByteString]), Map [Int] Int)
disassemblePresProgress (PresProgress progs)
         = ( ( compressPrPathSteps $ Arr.toList progStepRsr
             , Arr.toList progKeyRsr )
           , compressedProgs )
 where (ListT (WriterT keyCompressed), progStepRsr)
                  = rmRedundancy . ListT . WriterT $ Map.toList progs
       (compressedProgs,progKeyRsr) = rmRedundancy $ Map.fromList keyCompressed


-- | A hack to embed interactive values from JavaScript.
data ValueToSet = NoValGiven
                | ValueToSet { getValueToSet :: JSON.Value }
    deriving (Eq,Show,Read)

instance JSON.FromJSON ValueToSet where
  parseJSON = pure . ValueToSet

instance Flat ValueToSet where
  encode (ValueToSet v) = Flat.encode $ JSON.encode v
  encode NoValGiven = Flat.encode ()
  decode = do
     vj <- Flat.decode
     case JSON.eitherDecode vj of
       Left err -> fail err
       Right v -> pure v
  size (ValueToSet v) = Flat.size $ JSON.encode v

data PositionChangeKind
     = PositionAdvance
     | PositionRevert
     | PositionSetValue ValueToSet
  deriving (Generic, Eq, Show, Read)
instance JSON.FromJSON PositionChangeKind
instance Flat PositionChangeKind

data PositionChange = PositionChange
    { posChangeLevel :: PrPath
    , posChangeKind :: PositionChangeKind
    } deriving (Generic, Eq, Show, Read)
instance JSON.FromJSON PositionChange

instance PathPiece PositionChange where
  fromPathPiece = Txt.encodeUtf8
                 >>> preview _Right . URLBase64.decode
                 >=> preview _Right . fmap (uncurry PositionChange) . unflat
  toPathPiece (PositionChange lvl isRev)
                = Txt.decodeUtf8
                 <<< URLBase64.encode
                   $ flat (lvl, isRev)


instance PathPiece ValueToSet where
  fromPathPiece = Txt.encodeUtf8
                 >>> JSON.decodeStrict
                 >>> fmap ValueToSet
  toPathPiece NoValGiven = mempty
  toPathPiece (ValueToSet val) = Txt.decodeUtf8
                 <<< BSL.toStrict
                 <<< JSON.encode
                 $ val
