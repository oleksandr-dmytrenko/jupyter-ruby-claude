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
ENV JUPYTERLAB_VERSION="4.1.8"
ENV HTTPX_VERSION="0.27.2"

# Ruby
ENV RUBY_VERSION="3.3.4"
ENV BUNDLER_VERSION="2.5.16"
ENV GEM_IRUBY_VERSION="0.8.2"
ENV GEM_MYSQL2_VERSION="0.5.6"
ENV GEM_SEQUEL_VERSION="5.78.0"

# Setup keys to access internal git repositories
RUN mkdir -pv $HOME/.ssh
ADD ssh_config $HOME/.ssh/config
ADD stelladeploy_rsa $HOME/.ssh/stelladeploy_rsa
RUN chmod 600 $HOME/.ssh/*

# === System dependencies ===
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https autoconf bison build-essential ca-certificates curl git \
    imagemagick iputils-ping libbz2-dev libcurl4-openssl-dev libdb-dev libdbd-mysql-perl \
    libdbi-perl libffi-dev libgdbm-dev libgdbm6 libgmp-dev libgraphviz-dev libgvc6 \
    libio-socket-ssl-perl libjpeg62-turbo liblzma-dev libmagickcore-dev libmagickwand-dev \
    libmariadb-dev libncurses5-dev libncursesw5-dev libnet-libidn-perl libnet-ssleay-perl \
    libreadline-dev libreadline6-dev libsqlite3-dev libssl-dev libterm-readkey-perl libvips \
    libvips-dev libxml2-dev libxmlsec1-dev libyaml-dev libzmq3-dev pkg-config locales patch \
    rustc software-properties-common ssh telnet tk-dev tzdata uuid-dev vim wget xz-utils \
    zlib1g-dev && rm -rf /var/lib/apt/lists/*

# Install asdf
RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v${ASDF_VERSION}
ENV ASDF_DIR="${HOME}/.asdf"
ENV PATH="${HOME}/.local/bin:${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"
RUN . ~/.asdf/asdf.sh

# === Python / Poetry / Jupyter setup ===
RUN asdf plugin add python && \
    asdf install python $PYTHON_VERSION && \
    asdf global python $PYTHON_VERSION && \
    pip install pipx==$PIPX_VERSION && pipx ensurepath && pipx install poetry==$POETRY_VERSION

WORKDIR /nori-jupyter
RUN poetry new . && \
    poetry add ipykernel@"${IPYKERNEL_VERSION}" \
                ipywidgets@"${IPYWIDGETS_VERSION}" \
                jupyter-console@"${JUPYTER_CONSOLE_VERSION}" \
                nbconvert@"${NBCONVERT_VERSION}" \
                notebook@"${NOTEBOOK_VERSION}" \
                qtconsole@"${QTCONSOLE_VERSION}" \
                jupyterlab@"${JUPYTERLAB_VERSION}" \
                httpx=="${HTTPX_VERSION}" && \
    mkdir -p /notebooks

# === Ruby / IRuby setup ===
RUN asdf plugin add ruby && \
    asdf install ruby $RUBY_VERSION && \
    asdf global ruby $RUBY_VERSION && \
    gem install bundler -v $BUNDLER_VERSION && \
    gem install ffi-rzmq && \
    gem install mysql2 -v $GEM_MYSQL2_VERSION && \
    gem install sequel -v $GEM_SEQUEL_VERSION

# Install IRuby from gem, fallback to GitHub if fails
RUN gem install iruby -v $GEM_IRUBY_VERSION || \
    (gem install rake rake-compiler && \
     git clone --depth 1 https://github.com/SciRuby/iruby.git /tmp/iruby && \
     cd /tmp/iruby && rake install && rm -rf /tmp/iruby)

# Register IRuby kernel in Poetry environment
RUN poetry run iruby register --force

# === Rosi gem helpers ===
COPY rosi $HOME/rosi
WORKDIR $HOME/rosi
RUN gem build rosi.gemspec -o rosi.gem && gem install ./rosi.gem && rm rosi.gem
COPY rc.rb $HOME/rc.rb
ENV RUBYOPT="-r ${HOME}/rc.rb"

# === Final setup ===
WORKDIR /nori-jupyter
# Provide a minimal Gemfile for Bundler so IRuby doesn't complain about missing Gemfile
COPY Gemfile /nori-jupyter/Gemfile
ENV BUNDLE_GEMFILE="/nori-jupyter/Gemfile"
EXPOSE $PORT
CMD ["poetry", "run", "jupyter", "lab", "--ip=0.0.0.0", "--port=9999", "--no-browser", "--allow-root", "--IdentityProvider.token=", "--ServerApp.password=", "--ServerApp.root_dir=/notebooks"]
