#!/usr/bin/env stack
-- stack --resolver lts-15.10 script
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}


-- Copied from https://github.com/commercialhaskell/rio/blob/master/etc/make-template.hs


import           Conduit
import           RIO
import qualified RIO.ByteString       as B
import qualified RIO.ByteString.Lazy  as BL
import           RIO.FilePath
import           RIO.Process
import qualified RIO.Text             as T
import qualified RIO.Text.Partial     as T (replace)
import           RIO.Time
import qualified System.Environment   as Sys
import           Text.ProjectTemplate

data App = App
    { appLogFunc        :: !LogFunc
    , appProcessContext :: !ProcessContext
    }

instance HasLogFunc App where
  logFuncL = lens appLogFunc (\x y -> x { appLogFunc = y })
instance HasProcessContext App where
  processContextL = lens appProcessContext (\x y -> x { appProcessContext = y })

start :: RIO App a -> IO a
start inner = do
  appProcessContext <- mkDefaultProcessContext
  lo <- logOptionsHandle stderr True
  withLogFunc lo $ \appLogFunc -> runRIO App {..} inner

splitNulls :: ByteString -> [ByteString]
splitNulls bs
  | B.null bs = []
  | otherwise =
      let (x, y) = B.break (== 0) bs
       in x : splitNulls (B.drop 1 y)

decode :: ByteString -> RIO App FilePath
decode bs =
  case decodeUtf8' bs of
    Left e  -> throwIO e
    Right x -> return $ T.unpack x

readReplace :: MonadIO m => FilePath -> m ByteString
readReplace fp = do
  (year, _, _) <- toGregorian . utctDay <$> getCurrentTime
  encodeUtf8 . replaces year <$> readFileUtf8 fp
  where
    replaces year
      = T.replace "PROJECTNAME" "{{name}}"
      . T.replace "Paths_PROJECTNAME" "Paths_{{name-as-varid}}"
      . T.replace "AUTHOR" "{{author-name}}{{^author-name}}Author name here{{/author-name}}"
      . T.replace "MAINTAINER" "{{author-email}}{{^author-email}}example@example.com{{/author-email}}"
      . T.replace "GITHUB" "{{github-username}}{{^github-username}}githubuser{{/github-username}}/{{name}}"
      . T.replace "DESCRIPTION" "Please see the README on Github at <https://github.com/{{github-username}}{{^github-username}}githubuser{{/github-username}}/{{name}}#readme>"
      . T.replace "COPYRIGHT"
          (T.concat
             [ "{{copyright}}{{^copyright}}{{year}}{{^year}}"
             , T.pack $ show year
             , "{{/year}} {{author-name}}{{^author-name}}Author name here{{/author-name}}{{/copyright}}"
             ])

main :: IO ()
main = start $ do
  cliArgs <- liftIO Sys.getArgs
  (templateDir, outFile) <-
    case cliArgs
      of [t,o] -> pure (t,o)
         _     -> error "Usage: make-template.hs templatedir outfile"

  rawout <- withWorkingDir templateDir
          $ proc "git" ["ls-files", "-z"]
            readProcessStdout_
  files <- mapM decode $ splitNulls $ BL.toStrict rawout
  let src = forM_ files $ \fp -> yield (fp, readReplace $ templateDir </> fp)
  runConduitRes $ src .| createTemplate .| sinkFile outFile
