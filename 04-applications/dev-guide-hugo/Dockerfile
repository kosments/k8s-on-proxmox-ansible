# Build stage
FROM klakegg/hugo:alpine AS builder

WORKDIR /src

# Copy Hugo project
COPY config.toml .
COPY content/ content/

# Download theme
RUN mkdir -p themes && \
    wget -qO- https://github.com/alex-shpak/hugo-book/archive/master.tar.gz | \
    tar xz -C themes && \
    mv themes/hugo-book-master themes/book

# Build static site
RUN hugo --minify

# Production stage
FROM nginx:alpine

# Copy built site
COPY --from=builder /src/public /usr/share/nginx/html

# Custom nginx config for SPA routing
RUN echo 'server { \
    listen 80; \
    location / { \
        root /usr/share/nginx/html; \
        try_files $uri $uri/ /index.html; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

