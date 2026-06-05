#!/bin/sh
for f in recycler_onboarding.html reloop_poc.html dealer_portal.html; do
  sed -e "s|__SUPABASE_URL__|$SUPABASE_URL|g" \
      -e "s|__SUPABASE_ANON_KEY__|$SUPABASE_ANON_KEY|g" \
      /usr/share/nginx/html/$f > /tmp/$f
  mv /tmp/$f /usr/share/nginx/html/$f
done
exec nginx -g 'daemon off;'
