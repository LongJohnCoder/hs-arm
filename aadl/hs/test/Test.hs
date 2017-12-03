module Test where

import AADL.Lexer
import AADL.Tokens

test :: IO ()
test = do
    input <- readFile "test/test.aad"
    case scan input of
        Left err -> print err
        Right toks -> mapM_ print toks
