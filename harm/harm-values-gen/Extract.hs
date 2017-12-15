{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TupleSections #-}

module Extract
    ( encodingInfo
    ) where

import Harm.Types

import ARM.MRAS

import Control.Lens hiding (List)
import Data.Bits
import Data.Function
import Data.List
import Data.Monoid
import Data.Word
import Debug.Trace
import Control.Exception

encodingInfo :: [(Mnemonic, [(String, Pattern)])]
encodingInfo = map f (groupBy ((==) `on` (view _1 . fst)) (sortBy (compare `on` (view _1 . fst)) distilled))
  where
    f insn@(((mnem, _, _), _):_) = (mnem, map g insn)
    g ((_, id, patt), _) = (id, patt)

type Mnemonic = String
type EncodingInfo1 = (EncodingId, Mnemonic, Pattern)
type EncodingInfo2 = (Mnemonic, String, Pattern)

everything :: [Insn]
everything = base ++ fpsimd

distilled :: [(EncodingInfo2, [EncodingInfo2])]
distilled = map f stitched
  where
    f (insn, aliases) = (g insn, map g aliases)
    g (encid, mnem, patt) = case stripPrefix mnem encid of
        Just ('_':rest) -> (mnem, rest, patt)

stitched :: [(EncodingInfo1, [EncodingInfo1])]
stitched = go insnEncodings aliasEncodings
  where
    go insns [] = map (, []) insns
    go (insn:insns) aliases = (insn, good) : go insns bad
      where
        (good, bad) = partition (isAlias (view _1 insn) . view _1) aliases

isAlias :: EncodingId -> EncodingId -> Bool
isAlias insn alias = reverse ('_':insn) `isPrefixOf` reverse alias

fancyPartition :: (a -> Maybe b) -> [a] -> ([b], [a])
fancyPartition f = go [] []
  where
    go good bad [] = (good, bad)
    go good bad (a:as) = case f a of
        Just b -> go (b:good) bad as
        Nothing -> go good (a:bad) as

insnEncodings, aliasEncodings :: [EncodingInfo1]
insnEncodings = everything^..traverse.insn_classes.traverse._1.to fromClass.traverse
aliasEncodings = everything^..traverse.insn_aliases.traverse.alias_class.to fromClass.traverse

fromClass :: Class -> [EncodingInfo1]
fromClass Class{..} = map (f _class_diagram) _class_encodings
  where
    f blocks Encoding{..} = (_encoding_id, takeMnemonic _encoding_template, patt)
      where
        patt = compilePattern (map _block_spec (bindDiagram blocks _encoding_diagram))

mnemonics :: [String]
mnemonics = nub $ map takeMnemonic templates

takeMnemonic :: String -> String
takeMnemonic = takeWhile (not . flip elem (" .{" :: String))

templates :: [String]
templates = sort $ everything ^.. traverse.classes.class_encodings.traverse.encoding_template
  where
    classes = insn_classes.traverse._1 <> insn_aliases.traverse.alias_class

compilePattern :: [BlockSpec] -> Pattern
compilePattern = go 32 [] []
  where
    go 0 pos neg [] =
        let pos' = Atom
                (foldr (.|.) 0 (map atom_spec pos))
                (foldr (.&.) 0 (map atom_mask pos))
        in Pattern pos'  neg
    go hi pos neg (BlockEq  bits : rest) = go (hi - length bits) (toAtom hi bits : pos) neg rest
    go hi pos neg (BlockNeq bits : rest) = go (hi - length bits) pos (toAtom hi bits : neg) rest

toAtom :: Int -> [Bit] -> Atom
toAtom hi bits = Atom
    (f (map (== I) bits))
    (f (map (/= X) bits))
  where
    f = flip shiftL (hi - length bits) . encodeBits

encodeBits :: [Bool] -> Word32
encodeBits = foldl' f 0
  where
    f acc False = shiftL acc 1
    f acc True  = shiftL acc 1 .|. 1
