#!/bin/sh
envsubst '${SUPABASE_URL} ${SUPABASE_ANON_KEY}' < /usr/share/nginx/html/recycler_onboarding.html > /tmp/recycler_onboarding.html
mv /tmp/recycler_onboarding.html /usr/share/nginx/html/recycler_onboarding.html
exec nginx -g 'daemon off;'
