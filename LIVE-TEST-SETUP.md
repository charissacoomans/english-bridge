# English Bridge — live test setup

The existing home page, placement test, lesson tools and local student records are not replaced. This adds a separate live test page at /live-test.html and a link from the existing home page.

## What the live portal does
- Students register and sign in on their own device.
- Students start the 20-question placement test.
- Answers sync to the database as they are selected.
- The teacher sees the active session, answered-question count and selected answers. The teacher view is read-only.
- After submission, the student immediately sees the score, indicative level and explanation for each question.
- The teacher sees the completed result and submitted answers.
- Database Row Level Security restricts access to the student and the assigned teacher.

## 1. Create a Supabase project
1. Open https://supabase.com/ and create a project on the Free plan.
2. Open Project Settings → API (or API Keys).
3. Copy the Project URL and the public publishable key (or legacy anon public key).
4. Never use the service_role/secret key in browser code.

## 2. Create the tables and security policies
1. Open Supabase → SQL Editor → New query.
2. Open live-test-setup.sql in this repository.
3. Paste the complete SQL and click Run.
4. Check that the query finishes successfully.

## 3. Add the project URL and public key to the live page
1. Open live-test.html in GitHub and click Edit (pencil).
2. Find the two lines near the top of the script:
   SUPABASE_URL = "PASTE_SUPABASE_PROJECT_URL_HERE"
   SUPABASE_ANON_KEY = "PASTE_SUPABASE_PUBLISHABLE_OR_ANON_KEY_HERE"
3. Replace the first value with your Supabase Project URL.
4. Replace the second value with your public publishable/anon key.
5. Do NOT use a service_role key.
6. Commit changes.

The publishable/anon key is designed to be present in public browser code; access is restricted by the SQL Row Level Security policies.

## 4. Create and activate your teacher account
1. Open https://charissacoomans.github.io/english-bridge/live-test.html
2. Use the right-hand form to create your account. For Teacher email, enter the same email you used to register.
3. Confirm your email (if Supabase asks), then sign in.
4. In Supabase → SQL Editor, run the following query after replacing the address with your own email:

   update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"teacher"}'::jsonb
   where lower(email) = lower('YOUR-TEACHER-EMAIL@example.com');

5. Sign out of the portal and sign in again. Your account will now open the Teacher Portal.

## 5. Invite students
1. Give students this link:
   https://charissacoomans.github.io/english-bridge/live-test.html
2. Students create an account with their name and their own email address.
3. In the Teacher email box they enter your exact teacher login email.
4. After they confirm their email and sign in, they start the placement test.
5. Keep your teacher portal open on your computer. Their answers and progress appear as they work.

## Important notes
- This is a live classroom diagnostic, not a secure proctored examination. Students could still use other devices or outside help.
- The short test estimates a written level only; it is not an official CEFR certificate. Add a speaking, listening and writing check.
- Do not collect sensitive personal information. Do not publish service_role secrets.
- Supabase Free has usage limits and may pause inactive projects. Confirm current limits on Supabase's pricing page.
- The live portal is not active until the Supabase project is created, the SQL is run, and the two public client values are added to live-test.html.
