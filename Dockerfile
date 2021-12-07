FROM couchbase:enterprise-6.6.1

COPY ./configure-node.sh /etc/service/config-couchbase/run
RUN chown -R couchbase:couchbase /etc/service
