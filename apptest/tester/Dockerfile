FROM gcr.io/cloud-marketplace-tools/testrunner:0.1.4

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    gettext \
    jq \
    uuid-runtime \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /bin/kubectl \
    https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
      && chmod 755 /bin/kubectl

COPY tests/basic-suite.yaml /tests/basic-suite.yaml
COPY tester.sh /tester.sh

WORKDIR /
RUN chmod 755 tester.sh
ENTRYPOINT ["/tester.sh"]
