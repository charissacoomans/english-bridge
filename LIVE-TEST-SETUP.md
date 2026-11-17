# English Bridge — live test setup

The existing English Bridge home page and tutor tools remain in place. The live test is a separate page:

https://charissacoomans.github.io/english-bridge/live-test.html

## Already completed
- Supabase project english-bridge-live created and active in Tokyo.
- Tables profiles and test_sessions created.
- Row Level Security policies applied.
- Live Realtime publication enabled for test_sessions.
- Server-side grading trigger installed. The browser does not contain the answer key.
- Supabase project URL and public publishable key added to live-test.html.
- Home page contains a link to the Live student test.

## One-time setup you still need to do

### 1. Configure email confirmation redirects
1. Open Supabase → Authentication → URL Configuration.
2. Set Site URL to:
   https://charissacoomans.github.io/english-bridge/live-test.html
3. Add this exact URL to Redirect URLs:
   https://charissacoomans.github.io/english-bridge/live-test.html
4. Save.

This lets Supabase return users to the live test page after confirming their account.

### 2. Create your teacher account
1. Open the live test URL above.
2. In Create student account, enter your name, your email, a password of at least 8 characters, and your own email again in Your teacher's email address.
3. Create the account and confirm your email if Supabase asks.
4. Sign in to the live test page.

### 3. Promote your account to teacher
In Supabase → SQL Editor → New query, run the following, replacing the example email with the exact email you used to register:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"teacher"}'::jsonb
where lower(email) = lower('YOUR-TEACHER-EMAIL@example.com');
```

Then sign out of the live test page and sign back in. Your Teacher Portal will open.

### 4. Add students
1. Give students this link:
   https://charissacoomans.github.io/english-bridge/live-test.html
2. They create an account with their name and their own email.
3. In Your teacher's email address, they enter your exact teacher login email.
4. After confirming their email and signing in, they start the placement test.
5. Keep your Teacher Portal open on your computer. The live session progress and selected answers appear there.

## What is visible
- While the student is taking the test, you see the questions answered so far and the selected option.
- During the live test, the answer key is not sent to the teacher dashboard.
- When the student submits, Supabase calculates the score and returns the feedback. The student sees their result immediately, and you see the completed score and answer review.
- Teacher monitoring is view-only. You cannot edit student answers or pause the test.

## Security and limitations
- Never use or publish the Supabase service_role or secret key. The website uses only the public publishable key.
- Row Level Security restricts session access to the student and the teacher email attached to that session. Teacher access is granted by app_metadata.role = teacher, which you set in SQL as the project owner.
- This is a learning diagnostic, not a proctored exam. Students could use other devices or outside assistance.
- The test is an informal written screening, not an official CEFR certificate. Add speaking, listening and writing checks before assigning a final level.
- Avoid collecting sensitive personal information.
