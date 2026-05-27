FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
COPY recycler_onboarding.html /usr/share/nginx/html/recycler_onboarding.html
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
EXPOSE 80
ENTRYPOINT ["/docker-entrypoint.sh"]
