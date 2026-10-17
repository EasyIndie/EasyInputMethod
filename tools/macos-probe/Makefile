# macOS 实机验证探针：只读/受控操作，不进入产品。
SWIFT ?= swiftc
FLAGS ?= -O
BIN   := bin
SRCS  := $(wildcard *.swift)
BINS  := $(patsubst %.swift,$(BIN)/%,$(SRCS))

all: $(BINS)

$(BIN)/%: %.swift | $(BIN)
	$(SWIFT) $(FLAGS) $< -o $@

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -rf $(BIN)
