PROJECT = giphybot
ROOT_DIR = $(realpath .)
INTERACTIVE = -it --rm
CABAL_DIR = $(realpath ./.cabal)
GHC_DIR = $(realpath ./.ghc)

all: dirs docker update install

docker:
	sudo docker build -t $(PROJECT) .

upload:
	docker tag -f $(PROJECT) sgillis/$(PROJECT)
	docker push sgillis/$(PROJECT)

repl:
	docker run \
		$(INTERACTIVE) \
		-v $(HOME):$(HOME) \
		-v $(PWD):/src \
		-v $(CABAL_DIR):/root/.cabal \
		-v $(GHC_DIR):/root/.ghc \
		$(PROJECT) \
		cabal repl

bash:
	docker run \
		$(INTERACTIVE) \
		-v $(PWD):/src \
		-v $(CABAL_DIR):/root/.cabal \
		-v $(GHC_DIR):/root/.ghc \
		$(PROJECT) \
		/bin/bash

dirs:
	mkdir -p .cabal
	mkdir -p .ghc

update:
	docker run \
		$(INTERACTIVE) \
		-v $(PWD):/src \
		-v $(CABAL_DIR):/root/.cabal \
		-v $(GHC_DIR):/root/.ghc \
		$(PROJECT) \
		cabal update

install:
	docker run \
		$(INTERACTIVE) \
		-v $(PWD):/src \
		-v $(CABAL_DIR):/root/.cabal \
		-v $(GHC_DIR):/root/.ghc \
		$(PROJECT) \
		cabal install -j

run:
	docker run \
		$(INTERACTIVE) \
		-v $(PWD):/src \
		-v $(CABAL_DIR):/root/.cabal \
		-v $(GHC_DIR):/root/.ghc \
		-p 8000:8000 \
		--env-file telegram.env \
		$(PROJECT) \
		cabal run
