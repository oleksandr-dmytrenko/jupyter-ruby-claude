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
ENV BUNDLER_VERSION="2.4.22"
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

# Setup rosi helpers gem
COPY rosi $HOME/rosi
WORKDIR $HOME/rosi
RUN gem build rosi.gemspec -o rosi.gem && gem install ./rosi.gem && rm rosi.gem
COPY rc.rb $HOME/rc.rb
ENV RUBYOPT="-r ${HOME}/rc.rb"

WORKDIR /nori-jupyter
EXPOSE $PORT
CMD poetry run jupyter notebook -y --ip='*' --port=$PORT --no-browser --allow-root --IdentityProvider.token=$TOKEN --ServerApp.password='' --ServerApp.notebook_dir='/notebooks'
