# jupyter-ruby

JupyterLab image with a Ruby (IRuby) kernel, ready to use. The container includes:
- Debian 12
- Python 3.12 managed by Poetry (JupyterLab, Notebook, etc.)
- Ruby 3.3.4 with IRuby preinstalled and registered

## Prerequisites
- Docker installed

## Build
```bash
docker build -t jupyter-ruby:rb-3.3.4 .
```

## Run
```bash
docker run --rm -it \
  -p 9999:9999 \
  -v "$PWD/notebooks:/notebooks" \
  jupyter-ruby:rb-3.3.4
```
Then open http://localhost:9999 in your browser. Create a new notebook and choose the Ruby kernel.

Notes:
- Notebooks are stored in /notebooks inside the container. Mount a host folder (as shown above) to persist them.
- The IRuby kernel is registered during build. If needed inside the running container, you can re‑register it with:
  ```bash
  poetry run iruby register --force
  ```
- The image starts JupyterLab without authentication. Use only in trusted environments or place behind a secure proxy.

## Useful commands (inside the container)
- List kernels: `poetry run jupyter kernelspec list`
- Ruby check: `ruby -v` and `ruby -e 'require "iruby"; puts IRuby::VERSION'`
