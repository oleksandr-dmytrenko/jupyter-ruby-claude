FROM debian:bookworm

ENV PYTHON_VERSION="3.12.2"
ENV RUBY_VERSION="2.7.8"
ENV HOME="/root"
ENV TOKEN=""

RUN mkdir -pv $HOME/.ssh
ADD ssh_config $HOME/.ssh/config
ADD stelladeploy_rsa $HOME/.ssh/stelladeploy_rsa
RUN chmod 600 $HOME/.ssh/*

RUN apt-get update && apt-get install -y curl git build-essential libssl-dev zlib1g-dev \
  libbz2-dev libreadline-dev libsqlite3-dev curl \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  autoconf patch rustc libyaml-dev libreadline6-dev \
  libgmp-dev libncurses5-dev libgdbm6 libgdbm-dev libdb-dev uuid-dev \
  libmariadb-dev
RUN git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
ENV ASDF_DIR="${HOME}/.asdf"
ENV PATH="${HOME}/.local/bin:${ASDF_DIR}/bin:${ASDF_DIR}/shims:${PATH}"
RUN . ~/.asdf/asdf.sh

# Python setup
RUN asdf plugin add python
RUN asdf install python $PYTHON_VERSION
RUN asdf global python $PYTHON_VERSION
RUN pip install pipx
RUN pipx ensurepath
WORKDIR /nori-jupyter
RUN pipx install poetry
RUN poetry new .
RUN poetry add jupyter
RUN mkdir -p /notebooks

# Ruby setup
RUN asdf plugin add ruby
RUN asdf install ruby $RUBY_VERSION
RUN asdf global ruby $RUBY_VERSION
RUN gem install bundler -v 2.4.22
RUN gem install iruby
RUN iruby register --force

EXPOSE 9999

CMD poetry run jupyter notebook -y --ip='*' --port=9999 --no-browser --allow-root --IdentityProvider.token=$TOKEN --ServerApp.password='' --ServerApp.notebook_dir='/notebooks'
