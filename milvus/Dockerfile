# Use official image as base
FROM milvusdb/milvus:v2.6.1

# Create non-root user (uid/gid 1000 is standard in most clusters)
RUN groupadd --gid 1000 milvus && \
    useradd --uid 1000 --gid milvus --shell /bin/bash --create-home milvus

# Fix permissions only where needed
RUN chown -R 1000:1000 /milvus/bin /milvus/lib && \
    chmod -R 755 /milvus/bin /milvus/lib

# Switch to non-root user
USER 1000:1000

# Keep original working directory and entrypoint
WORKDIR /milvus
EXPOSE 19530 9091

ENTRYPOINT ["/tini", "--", "/milvus/bin/milvus"]

CMD ["run", "standalone"]