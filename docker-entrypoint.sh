#!/bin/sh
sed -e "s|__SUPABASE_URL__|$SUPABASE_URL|g" \
    -e "s|__SUPABASE_ANON_KEY__|$SUPABASE_ANON_KEY|g" \
    /usr/share/nginx/html/recycler_onboarding.html > /tmp/recycler_onboarding.html
mv /tmp/recycler_onboarding.html /usr/share/nginx/html/recycler_onboarding.html
exec nginx -g 'daemon off;'
