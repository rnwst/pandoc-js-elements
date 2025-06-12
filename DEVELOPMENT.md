# Testing

## Install Luacov

```console
luarocks config local_by_default true
luarocks install busted
luarocks install luacov
luarocks install cluacov
```

## Run tests

```console
pandoc lua tests.lua
```

## Generating an HTML report

Ensure Luacov binary location is on `PATH`: `~/.luarocks/bin`. Then simply run
```console
luacov
```
