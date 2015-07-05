{-# LANGUAGE OverloadedStrings #-}

module Main where

import System.Environment
import Web.Spock.Safe
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.State as S
import Control.Monad
import Network.HTTP.Types.Status
import Network.URL
import Data.Text
import Data.Default
import Data.Maybe
import Network.Telegram
import Network.Giphy

telegramToken :: IO String
telegramToken = getEnv "TELEGRAM_TOKEN"

giphyToken = publicToken

data Command = SearchGiphy String
             | UnknownCommand
             deriving Show

data GiphyBotResponse = Giphy URL
                      | NoResponse
                      deriving Show

badRequest :: String -> ActionT IO ()
badRequest message = setStatus status400 >> json message

parseMessage :: String -> Command
parseMessage t | "/giphy " `isPrefixOf` (pack t) = SearchGiphy searchString
               | otherwise = UnknownCommand
    where Just searchString = unpack <$> stripPrefix "/giphy " (pack t)

execCmd :: Command -> IO GiphyBotResponse
execCmd UnknownCommand = return NoResponse
execCmd (SearchGiphy t) = do
    mpr <- search giphyToken (def { search_q = t, search_limit = 1 })
    case mpr of
        Nothing -> return NoResponse
        Just pr -> do
            let murl = getFirstResultURL' pr
            case murl of
                Nothing -> return NoResponse
                Just url -> return $ Giphy url

responseToMessage :: Int -> GiphyBotResponse -> SendMessageParams
responseToMessage id NoResponse = SendMessageParams
    { sendMessageChatId = id
    , sendMessageText = "Try /giphy <something>"
    , sendMessageDisableWebPagePreview = Nothing
    , sendMessageReplyToMessageId = Nothing
    }
responseToMessage id (Giphy url) = SendMessageParams
    { sendMessageChatId = id
    , sendMessageText = exportURL url
    , sendMessageDisableWebPagePreview = Nothing
    , sendMessageReplyToMessageId = Nothing
    }

getChatId :: Chat -> Int
getChatId (ChatUser u) = userId u
getChatId (ChatGroup g) = groupchatId g

getText :: Maybe Update -> Maybe String
getText mupdate = mupdate >>= updateMessage >>= messageText

getUpdateChatId :: Maybe Update -> Maybe Int
getUpdateChatId mupdate = mupdate >>= updateMessage >>=
                          return . getChatId . messageChat

head' :: [a] -> Maybe a
head' [] = Nothing
head' (x:_) = Just x

getFirstGiphy' :: PaginatedResult -> Maybe GiphyResult
getFirstGiphy' pr = head' . result $ pr

getFirstResultURL' :: PaginatedResult -> Maybe URL
getFirstResultURL' pr = getOriginalImageURL <$> getFirstGiphy' pr

giphybot :: SpockT IO ()
giphybot = do
    Web.Spock.Safe.get root $ json ("GiphyBot" :: String)
    post "webhook" $ do
        mupdate <- jsonBody :: ActionT IO (Maybe Update)
        let text = fromMaybe "" (getText mupdate)
        let mcid = getUpdateChatId mupdate
        case mcid of
            Nothing -> badRequest "Unable to parse Update"
            Just id -> do
                let cmd =  parseMessage text
                r <- liftIO $ execCmd cmd
                let m = responseToMessage id r
                liftIO $ print $ sendMessageText m
                t <- liftIO telegramToken
                liftIO $ print t
                _ <- liftIO $ sendMessage t m
                json ("Ok" :: String)

runGiphybot :: IO ()
runGiphybot = runSpock 8000 $ spockT Prelude.id $ giphybot

updateToCommand :: Update -> Command
updateToCommand u = case mc of
    Nothing -> UnknownCommand
    Just c  -> c
    where mc = updateMessage u >>= messageText >>= return . parseMessage

maximum' :: Ord a => [a] -> Maybe a
maximum' [] = Nothing
maximum' xs = Just (Prelude.maximum xs)

processUpdates :: String -> StateT Int IO ()
processUpdates token = do
    lastId <- S.get
    liftIO $ print $ "Looking for updates from ID: " ++ show lastId
    mresponse <- liftIO $
        getUpdates token (def { getUpdatesOffset = Just lastId })
    let response = fromMaybe
                   (TelegramResponse { responseOk = True
                                     , responseResult = Nothing
                                     , responseDescription = Nothing })
                   mresponse
    let updates = fromMaybe [] (responseResult response)
    let commands = Prelude.map updateToCommand updates
    let mmessages = Prelude.map (updateMessage) updates
    let mids = Prelude.map ((getChatId . messageChat) <$>) mmessages
    let mlastId' = maximum' $ Prelude.map updateId updates
    giphyResponses <- liftIO $ forM commands execCmd
    let idsAndResponses = Prelude.zip mids giphyResponses
    let msendParams = Prelude.map (\(mid,r) -> flip responseToMessage r <$> mid) idsAndResponses
    let sendParams = catMaybes msendParams
    liftIO $ forM_ sendParams (sendMessage token)
    case mlastId' of
        Nothing -> return ()
        Just id -> S.put (id + 1)
    processUpdates token

main :: IO ()
main = do
    t <- telegramToken
    S.evalStateT (processUpdates t) (635723122 :: Int)
