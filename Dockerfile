FROM debian:12.5

# Base
ENV HOME="/root"
ENV PORT="9999"
ENV TOKEN=""
ENV ASDF_VERSION="0.14.0"

# Python
ENV PYTHON_VERSION="3.12.2"
ENV PIPX_VERSION="1.4.3"
ENV POETRY_VERSION="1.8.2"
ENV IPYKERNEL_VERSION="6.29.3"
ENV IPYWIDGETS_VERSION="8.1.2"
ENV JUPYTER_CONSOLE_VERSION="6.6.3"
ENV NBCONVERT_VERSION="7.16.2"
ENV NOTEBOOK_VERSION="7.1.2"
ENV QTCONSOLE_VERSION="5.5.1"

# Ruby
ENV RUBY_VERSION="3.3.4"
ENV BUNDLER_VERSION="2.5.15"
ENV GEM_IRUBY_VERSION="0.7.4"
ENV GEM_MYSQL2_VERSION="0.5.6"
ENV GEM_SEQUEL_VERSION="5.78.0"

# Setup keys to access internal git repositories
RUN mkdir -pv $HOME/.ssh
ADD ssh_config $HOME/.ssh/config
ADD stelladeploy_rsa $HOME/.ssh/stelladeploy_rsa
RUN chmod 600 $HOME/.ssh/*

# Install system dependencies
RUN apt-get update
RUN TZ=Etc/UTC DEBIAN_FRONTEND=noninteractive apt-get install -y \
      apt-transport-https \
      autoconf \
      bison \
      build-essential \
      ca-certificates \
      curl \
      ghostscript \
      git \
      imagemagick \
      iputils-ping \
      libbz2-dev \
      libcurl4-openssl-dev \
      libdb-dev \
      libdbd-mysql-perl \
      libdbi-perl \
      libffi-dev \
      libgdbm-dev \
      libgdbm6 \
      libgmp-dev \
      libgraphviz-dev \
      libgvc6 \
      libio-socket-ssl-perl \
      libjpeg62-turbo \
      liblzma-dev \
      libmagickcore-dev \
      libmagickwand-dev \
      libmariadb-dev \
      libncurses5-dev \
      libncursesw5-dev \
      libnet-libidn-perl \
      libnet-ssleay-perl \
      libreadline-dev \
      libreadline6-dev \
      libsqlite3-dev \
      libssl-dev \
      libterm-readkey-perl \
      libvips \
      libvips-dev \
      libxml2-dev \
      libxmlsec1-dev \
      libyaml-dev \
      locales \
      patch \
      rustc \
      software-properties-common \
      ssh \
      telnet \
      tk-dev \
      tzdata \
      uuid-dev \
      vim \
      wget \
      xz-utils \
      zlib1g-dev

# Install asdf
RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v${ASDF_VERSION}
ENV ASDF_DIR="${HOME}/.asdf"
ENV PATH="${HOME}/.local/bin:${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"
RUN . ~/.asdf/asdf.sh

# Python & Jupyter setup
RUN asdf plugin add python
RUN asdf install python $PYTHON_VERSION
RUN asdf global python $PYTHON_VERSION
RUN pip install pipx==$PIPX_VERSION
RUN pipx ensurepath
WORKDIR /nori-jupyter
RUN pipx install poetry==$POETRY_VERSION
RUN poetry new .
RUN poetry add ipykernel@"${IPYKERNEL_VERSION}"
RUN poetry add ipywidgets@"${IPYWIDGETS_VERSION}"
RUN poetry add jupyter-console@"${JUPYTER_CONSOLE_VERSION}"
RUN poetry add nbconvert@"${NBCONVERT_VERSION}"
RUN poetry add notebook@"${NOTEBOOK_VERSION}"
RUN poetry add qtconsole@"${QTCONSOLE_VERSION}"
RUN mkdir -p /notebooks

# Ruby & Ruby kernel setup
RUN asdf plugin add ruby
RUN asdf install ruby $RUBY_VERSION
RUN asdf global ruby $RUBY_VERSION
RUN gem install bundler -v $BUNDLER_VERSION
RUN gem install iruby -v $GEM_IRUBY_VERSION
RUN gem install mysql2 -v $GEM_MYSQL2_VERSION
RUN gem install sequel -v $GEM_SEQUEL_VERSION
RUN iruby register --force
ENV BUNDLE_GEMFILE=""

# Fix IRuby kernel to work with poetry environment
RUN poetry run iruby register --force

# Create a proper working directory for IRuby
WORKDIR /nori-jupyter
RUN mkdir -p /nori-jupyter/.jupyter

# Create a proper Ruby kernel configuration
RUN echo '{' > /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "argv": [' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "/root/.asdf/shims/iruby",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "kernel",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "{connection_file}"' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' ],' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "display_name": "Ruby 3.3.4",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "language": "ruby",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "env": {' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "PATH": "/root/.cache/pypoetry/virtualenvs/nori-jupyter-GHB3VKFG-py3.12/bin:/root/.asdf/shims:/root/.asdf/installs/ruby/3.3.4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "BUNDLE_GEMFILE": "",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "WORKING_DIR": "/nori-jupyter",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "GEM_HOME": "/root/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "GEM_PATH": "/root/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0"' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' }' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '}' >> /root/.local/share/jupyter/kernels/ruby/kernel.json

# Create a wrapper script for IRuby to handle bundler issues
RUN echo '#!/bin/bash' > /usr/local/bin/iruby-wrapper && \
    echo 'export BUNDLE_GEMFILE=""' >> /usr/local/bin/iruby-wrapper && \
    echo 'export GEM_HOME="/root/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0"' >> /usr/local/bin/iruby-wrapper && \
    echo 'export GEM_PATH="/root/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0"' >> /usr/local/bin/iruby-wrapper && \
    echo 'cd /nori-jupyter' >> /usr/local/bin/iruby-wrapper && \
    echo 'exec /root/.asdf/shims/iruby "$@"' >> /usr/local/bin/iruby-wrapper
RUN chmod +x /usr/local/bin/iruby-wrapper

# Copy custom IRuby kernel
COPY iruby_kernel.py /usr/local/bin/iruby_kernel.py
RUN chmod +x /usr/local/bin/iruby_kernel.py

# Update kernel to use custom Python-based IRuby kernel
RUN echo '{' > /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "argv": [' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "python",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "/usr/local/bin/iruby_kernel.py",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "-f",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "{connection_file}"' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' ],' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "display_name": "IRuby 3.3.4",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "language": "ruby",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' "env": {' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "PATH": "/root/.cache/pypoetry/virtualenvs/nori-jupyter-GHB3VKFG-py3.12/bin:/root/.asdf/shims:/root/.asdf/installs/ruby/3.3.4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "BUNDLE_GEMFILE": "",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "WORKING_DIR": "/nori-jupyter",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "GEM_HOME": "/root/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0",' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '  "GEM_PATH": "/root/.asdf/installs/ruby/3.3.4/lib/ruby/gems/3.3.0"' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo ' }' >> /root/.local/share/jupyter/kernels/ruby/kernel.json && \
    echo '}' >> /root/.local/share/jupyter/kernels/ruby/kernel.json

# Setup rosi helpers gem
COPY rosi $HOME/rosi
WORKDIR $HOME/rosi
RUN gem build rosi.gemspec -o rosi.gem && gem install ./rosi.gem && rm rosi.gem
COPY rc.rb $HOME/rc.rb
ENV RUBYOPT="-r ${HOME}/rc.rb"

WORKDIR /nori-jupyter
EXPOSE $PORT
CMD poetry run jupyter notebook -y --ip='*' --port=$PORT --no-browser --allow-root --IdentityProvider.token=$TOKEN --ServerApp.password='' --ServerApp.notebook_dir='/notebooks'
