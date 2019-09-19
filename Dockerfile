FROM alpine:3
RUN apk add --no-cache \
  curl jq

COPY main.sh /usr/local/bin/ip-operator
ENTRYPOINT ["/usr/local/bin/ip-operator"]
