import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { firebase_uid, phone } = await req.json()

    if (!firebase_uid || !phone) {
      return new Response(
        JSON.stringify({ error: 'firebase_uid and phone are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase admin client
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { auth: { autoRefreshToken: false, persistSession: false } }
    )

    // Check if user exists in users table by phone
    const { data: existingUser } = await supabaseAdmin
      .from('users')
      .select('id, full_name, role')
      .eq('phone', phone)
      .maybeSingle()

    let userId: string

    if (existingUser) {
      // Existing user — use their ID
      userId = existingUser.id
      console.log('Existing user found:', userId)
    } else {
      // New user — will be created after name collection
      // For now return signal that user is new
      return new Response(
        JSON.stringify({ is_new_user: true }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if Supabase auth user exists
    const { data: authData } = await supabaseAdmin.auth.admin.getUserById(userId)

    let supabaseUserId = userId

    if (!authData.user) {
      // Create Supabase auth user with phone
      const { data: newAuthUser, error: authError } =
        await supabaseAdmin.auth.admin.createUser({
          phone:              phone.replace('+', ''),
          phone_confirm:      true,
          user_metadata:      { firebase_uid },
        })

      if (authError) {
        console.error('Auth user creation error:', authError)
        throw authError
      }

      supabaseUserId = newAuthUser.user.id

      // Update users table with correct auth ID
      await supabaseAdmin
        .from('users')
        .update({ id: supabaseUserId })
        .eq('phone', phone)
    }

    // Generate a Supabase session for this user
    const { data: sessionData, error: sessionError } =
      await supabaseAdmin.auth.admin.generateLink({
        type:  'magiclink',
        email: `${supabaseUserId}@cleenzo.app`,
      })

    if (sessionError) throw sessionError

    // Alternative: create a custom token
    // Return user info so Flutter can set up session
    return new Response(
      JSON.stringify({
        is_new_user:  false,
        user_id:      supabaseUserId,
        full_name:    existingUser?.full_name,
        role:         existingUser?.role ?? 'customer',
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})