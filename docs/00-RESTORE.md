# RESTORE - נקודת עצירה (יומנון)

עודכן: 2026-11-07 | commit: ראו `git log -1` ב-main | ספרינט: 3 (מיתוג: יומנון, סקינים, פונטים)

## איפה הקוד
- GitHub: https://github.com/maayantallevy-lang/event-log (ענף main; לשעבר baby-log). זה הקוד הרץ.
- Drive (SSOT לתיעוד וגיבוי): תיקיית "יומן אירועים" - `01 מסמכי יסוד` (המסמכים האלה), `02 קוד` (עותק של כל קובץ מקור; פונטים לא - ראו README שם), `03 הדגמה` (דף HTML להדגמה), `04 מיתוג` (לוגואים SVG), `08 פריסה ותפעול` (קישורי Release והתקנה).
- APK: GitHub Releases של הריפו (כל push ל-main בונה, חותם ומפרסם Release עם APK ו-sha256).

## איך משחזרים סביבה
```bash
git clone https://github.com/maayantallevy-lang/event-log && cd event-log
flutter pub get && flutter analyze && flutter build apk --release
```
- בנייה מקומית בלי `android/key.properties` נחתמת במפתח debug (לא מתעדכנת מעל גרסה חתומה).
- הסביבה של Claude לא יכולה להוריד חבילות (pub.dev חסום) ולא Android SDK. לכן: כותבים קוד, דוחפים, ו-GitHub Actions מקמפל.
- Drive: דרך מחבר Drive של Claude. אין עדכון תוכן במקום - קובץ שמשתנה מועלה מחדש והישן לאשפה.

## חתימה (D-14)
- keystore קבוע: alias `upload`. גיבוי: Drive, תיקייה פרטית "99 סודות" (upload.jks + קובץ סיסמה). לא בריפו.
- GitHub Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`. ה-workflow נכשל אם חסרים.
- SHA-1: 8A:2A:9E:4C:99:59:18:E3:58:00:2F:B4:21:10:97:2C:50:38:70:B3

## Google Cloud (סנכרון Drive, D-13)
- פרויקט: `event-log-514014` (חשבון המבקש). Drive API פעיל. מסך הסכמה: External, Testing, משתמש בדיקה: חשבון המבקש בלבד.
- OAuth Android: חבילה `il.co.maayan.eventlog` + SHA-1 למעלה.
- OAuth Web (serverClientId): `494572279154-3pkmvau9hqa3gorvq0jg2kotvojj498o.apps.googleusercontent.com` - מוטבע ב-`lib/services/drive_sync.dart`. לא סוד.
- מגבלה: בסטטוס Testing רק משתמשי בדיקה יכולים להתחבר. לשיתוף עם אחרים: להוסיף אותם כמשתמשי בדיקה או לעבור לאימות.

## מצב
- ירוק: S0, S1 (MVP תינוק, v0.1).
- ירוק: S2 - v0.2.0 כללי (תבניות: תינוק/הריון/בריאות/ריק), סכימה v2 עם מזהים גלובליים, סנכרון Drive. לא נבדק על מכשיר.
- רץ: S3 - v0.3.0 "יומנון": 4 סקינים, 5 פונטים מקומיים (assets/fonts), מסך "מראה". לוגו: נבחרה הצעה B (ציר זמן), מוטמע כאייקון (D-20). מקור: `04 מיתוג` בדרייב, לוח עיצוב https://claude.ai/artifact/6pTMYHb4URBVLGKjd9EypG.

## הצעד הבא
- המבקש מסיר את v0.1 (מזהה וחתימה שונים), מתקין את הגרסה האחרונה מ-Releases, בוחר "בגוגל דרייב שלי" ומדווח.
- אחר כך: ווידג'ט, אנגלית, AdMob.

## איך המבקש עובד
- עברית בלבד, 3-6 שורות, צעד ידני אחד בכל פעם, פקודה בבלוק משלה.
- כל קובץ חייב להיות ב-Drive; הסביבה של Claude מתאפסת.
- Claude הוא החשבון של המבקש (מעיין), לא של לקוחות שלו.
- דפדפן: הכרום של המבקש (לא הדפדפן המובנה).
