VERSION ?= 23.10
CODENAME ?= mantic

.PHONY: clean
clean:
	rm -rf img

.PHONY: img
img:
	VERSION=$(VERSION) CODENAME=$(CODENAME) ./download.sh
