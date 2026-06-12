import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { code, redirect_uri } = await req.json()
    if (!code || !redirect_uri) {
      return new Response(JSON.stringify({ error: 'Missing code or redirect_uri' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const LINE_CHANNEL_ID      = Deno.env.get('LINE_CHANNEL_ID')!
    const LINE_CHANNEL_SECRET  = Deno.env.get('LINE_CHANNEL_SECRET')!
    const SUPABASE_URL         = Deno.env.get('SUPABASE_URL')!
    const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // 1. 用 code 換 LINE access_token
    const tokenRes = await fetch('https://api.line.me/oauth2/v2.1/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type:    'authorization_code',
        code,
        redirect_uri,
        client_id:     LINE_CHANNEL_ID,
        client_secret: LINE_CHANNEL_SECRET,
      }),
    })
    const tokenData = await tokenRes.json()
    if (!tokenData.access_token) {
      return new Response(JSON.stringify({ error: 'LINE token exchange failed', detail: tokenData }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 2. 取得 LINE 用戶資料
    const profileRes = await fetch('https://api.line.me/v2/profile', {
      headers: { Authorization: `Bearer ${tokenData.access_token}` },
    })
    const profile = await profileRes.json()
    const lineUserId    = profile.userId
    const displayName   = profile.displayName
    const pictureUrl    = profile.pictureUrl || null

    // 3. 查 recycler_onboarding_accounts 有無此 line_user_id
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const { data: account } = await supabase
      .from('recycler_onboarding_accounts')
      .select('id, company_name, contact_name, phone')
      .eq('line_user_id', lineUserId)
      .single()

    if (!account) {
      // 尚未綁定帳號，需要引導到登入/註冊
      return new Response(JSON.stringify({
        needs_link: true,
        line_user_id:  lineUserId,
        display_name:  displayName,
        picture_url:   pictureUrl,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 4. 建立 Supabase session（account.id 即為 auth.users.id）
    const { data: sessionData, error: sessionError } = await supabase.auth.admin.createSession({
      user_id: account.id,
    })

    if (sessionError) {
      return new Response(JSON.stringify({ error: sessionError.message }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response(JSON.stringify({
      access_token:  sessionData.session.access_token,
      refresh_token: sessionData.session.refresh_token,
      account: {
        id:           account.id,
        company_name: account.company_name,
        contact_name: account.contact_name,
      },
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
