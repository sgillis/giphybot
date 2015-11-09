FROM sgillis/hdevtools

RUN git clone https://github.com/sgillis/telegram.git
RUN git clone https://github.com/sgillis/hiphy.git
WORKDIR /telegram
RUN cabal install -j
WORKDIR /hiphy
RUN cabal install -j

RUN mkdir /src
WORKDIR /src

ADD giphybot.cabal /src/giphybot.cabal
RUN cabal install --dependencies-only
ADD src /src/src
RUN cabal configure
RUN cabal build
