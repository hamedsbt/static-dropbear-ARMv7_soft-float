# Dropbear SSH برای Huawei B612s-25d

یک سرور SSH مبتنی بر Dropbear، به‌صورت استاتیک و مخصوص روتر Huawei B612s-25d.

این پروژه برای محیط firmware روتر Huawei B612s-25d طراحی شده و با استفاده از دسترسی root از طریق ADB، یک Dropbear استاتیک برای معماری ARMv7 نصب می‌کند.

## دستگاه هدف

روی محیط زیر آزمایش شده است:

```text
Device        : Huawei B612s-25d
Hardware      : WL1B612M01
Android       : 4.4.1
Kernel        : Linux 3.10.59+ armv7l
Software      : 81.201.01.01.234
Web UI        : 81.100.35.02.234
```

نصب‌کننده بر اساس ویژگی‌های زیر در firmware طراحی شده است:

```text
/system                    YAFFS2 و معمولاً فقط‌خواندنی پس از boot
/data                      YAFFS2 و قابل نوشتن
/system/etc/init.d/        وجود ندارد
/init.rc                   فایل /init.huawei.rc را import می‌کند
/init.huawei.rc            سرویس /system/etc/autorun.sh را اجرا می‌کند
```

بنابراین مکانیزم اجرای دائمی Dropbear از فایل موجود Huawei استفاده می‌کند:

```text
/system/etc/autorun.sh
```

هیچ تغییری در `/init.rc` یا `/init.huawei.rc` لازم نیست.

## امکانات

- سرور SSH مبتنی بر Dropbear
- باینری استاتیک ARMv7-A
- VFPv3-D16
- ABI از نوع softfp
- کلید host از نوع RSA
- کلید host از نوع ECDSA
- کلید host از نوع Ed25519
- احراز هویت با کلید عمومی
- تعیین صریح مسیر `authorized_keys`
- تشخیص خودکار home directory کاربر root از `/etc/passwd`
- اجرای دائمی پس از reboot
- انتظار برای آماده‌شدن رابط LAN قبل از اجرای Dropbear
- اجرای مجدد امن installer
- نگهداری نسخه اصلی `autorun.sh` شرکت Huawei
- installer برای Windows
- installer برای Linux/macOS
- بررسی هفتگی نسخه جدید Dropbear
- ساخت خودکار GitHub Release برای نسخه‌های جدید upstream

## ⚠️ هشدار درباره احراز هویت با رمز عبور

### ورود SSH با رمز عبور در فریمور Huawei B612 پشتیبانی نمی‌شود

در فریمور آزمایش‌شده‌ی Huawei B612s-25d، احراز هویت SSH با رمز عبور به دلیل نحوه مدیریت حساب کاربری root و پایگاه داده‌ی رمز عبور در سیستم Huawei/Android به‌درستی کار نمی‌کند.

دستگاه فایل زیر را دارد:

```text
/system/etc/passwd
```

و حساب root به شکل زیر ثبت شده است:

```text
root::0:0:root:/data/root-home:/bin/sh
```

همچنین در فریمور آزمایش‌شده فایل قابل استفاده‌ای در مسیر زیر وجود ندارد:

```text
/etc/shadow
```

اگرچه دستور `passwd` موجود در BusyBox تغییر رمز عبور را ظاهراً با موفقیت انجام می‌دهد، هش رمز عبور به شکلی ذخیره نمی‌شود که Dropbear بتواند از آن برای احراز هویت SSH استفاده کند. در نتیجه Dropbear ورود با رمز عبور را رد می‌کند، حتی اگر دستور `passwd` پیام موفقیت نمایش دهد.

بنابراین این مشکل مربوط به شبکه یا سرویس SSH نیست؛ بلکه یک محدودیت در نحوه مدیریت حساب کاربری و رمز عبور توسط فریمور Huawei است.

### استفاده از کلید SSH به‌جای رمز عبور

این پروژه برای همین دلیل از **احراز هویت با کلید عمومی SSH** استفاده می‌کند.

کلید عمومی خود را در مسیر زیر قرار دهید:

```text
/data/root-home/.ssh/authorized_keys
```

کلید خصوصی باید فقط روی کامپیوتر شما باقی بماند.

برای مثال:

```sh
ssh -i ~/.ssh/your_private_key root@192.168.0.217
```

بنابراین برای ورود SSH به این روتر روی دستور `passwd` برای فعال‌سازی ورود با رمز عبور حساب نکنید.

Dropbear از کلیدهای RSA، Ed25519 و ECDSA از طریق فایل `authorized_keys` پشتیبانی می‌کند.

## ساختار repository

```text
B612-Dropbear/
├── install-dropbear.sh
├── install-dropbear.bat
├── README.md
├── README.fa.md
├── LICENSE
└── .github/
    └── workflows/
        └── build-dropbear.yml
```

فایل `dropbear-start` داخل repository یا release قرار نمی‌گیرد.

این فایل توسط installer ساخته می‌شود، زیرا تنظیمات آن شامل IP روتر و home directory کاربر root است که مستقیماً از دستگاه هدف استخراج می‌شوند.

## Releaseها

بسته‌های Release به‌صورت خودکار از نسخه upstream Dropbear ساخته می‌شوند.

ساختار بسته:

```text
DROPBEAR_<version>_armv7_soft-float_static_B612-25d.zip
├── dropbear
├── dropbearkey
├── install-dropbear.sh
├── install-dropbear.bat
└── BUILD-INFO.txt
```

GitHub Actions هر هفته نسخه upstream Dropbear را بررسی می‌کند.

در صورت پیدا شدن نسخه جدید `DROPBEAR_*`، workflow مراحل زیر را انجام می‌دهد:

1. دریافت source رسمی upstream.
2. cross-compile برای ARMv7-A.
3. استفاده از VFPv3-D16.
4. استفاده از ABI نوع softfp.
5. ساخت باینری‌های static.
6. بررسی فایل‌های ELF.
7. بررسی نسخه Dropbear.
8. ساخت بسته Release.
9. ایجاد خودکار GitHub Release.

همچنین workflow را می‌توان به‌صورت دستی اجرا کرد.

برای ساخت Release، workflow به permission زیر نیاز دارد:

```yaml
permissions:
  contents: write
```

## هدف build

باینری‌ها با گزینه‌های زیر ساخته می‌شوند:

```text
-march=armv7-a
-mfpu=vfpv3-d16
-mfloat-abi=softfp
-static
```

باینری حاصل برای محیط ARMv7 روتر B612s-25d در نظر گرفته شده است.

## پیش‌نیازها

### روتر

روتر باید موارد زیر را داشته باشد:

- ADB از طریق TCP
- دسترسی root از طریق ADB
- امکان remount کردن `/system` به حالت read-write
- سرویس Huawei مربوط به `autorun.sh`

آدرس پیش‌فرض ADB:

```text
192.168.8.1:5555
```

### Windows

Android Platform Tools را نصب کنید و مطمئن شوید:

```text
adb.exe
```

در `PATH` سیستم قرار دارد.

این فایل‌ها را در یک پوشه قرار دهید:

```text
install-dropbear.bat
dropbear
dropbearkey
```

### Linux / macOS

باید:

```text
adb
```

در `PATH` موجود باشد.

این فایل‌ها را کنار هم قرار دهید:

```text
install-dropbear.sh
dropbear
dropbearkey
```

## نصب در Windows

با آدرس پیش‌فرض روتر:

```cmd
install-dropbear.bat
```

با مشخص‌کردن IP روتر:

```cmd
install-dropbear.bat 192.168.8.1
```

با مشخص‌کردن endpoint کامل ADB:

```cmd
install-dropbear.bat 192.168.8.1:5555
```

installer این مراحل را انجام می‌دهد:

1. بررسی باینری‌های محلی Dropbear.
2. اتصال به ADB.
3. درخواست root برای ADB.
4. بررسی دستگاه ARMv7.
5. خواندن entry مربوط به root از `/etc/passwd`.
6. تشخیص home directory کاربر root.
7. remount کردن `/system` به حالت read-write.
8. ساخت directoryهای Dropbear.
9. نصب `dropbear` و `dropbearkey`.
10. ساخت کلیدهای host دائمی.
11. ساخت `/system/bin/dropbear-start`.
12. نصب hook دائمی در `autorun.sh`.
13. بررسی نهایی نصب.

installer بلافاصله Dropbear را اجرا نمی‌کند.

پس از اتمام نصب، روتر را reboot کنید.

## نصب در Linux / macOS

ابتدا installer را executable کنید:

```bash
chmod +x install-dropbear.sh
```

سپس با IP پیش‌فرض اجرا کنید:

```bash
./install-dropbear.sh
```

یا IP روتر را مشخص کنید:

```bash
./install-dropbear.sh 192.168.8.1
```

یا endpoint کامل ADB را بدهید:

```bash
./install-dropbear.sh 192.168.8.1:5555
```

پس از نصب، روتر را reboot کنید.

## احراز هویت با کلید عمومی SSH

installer entry کاربر root را از:

```text
/etc/passwd
```

می‌خواند.

ساختار `/etc/passwd` به این شکل است:

```text
name:password:UID:GID:GECOS:directory:shell
```

فیلد ششم، home directory کاربر است.

برای مثال:

```text
root::0:0:root:/data/root-home:/bin/sh
```

به این مقادیر تبدیل می‌شود:

```text
ROOT_HOME=/data/root-home
ROOT_SSH_DIR=/data/root-home/.ssh
```

بنابراین محل صحیح کلیدهای SSH:

```text
/data/root-home/.ssh/authorized_keys
```

است.

نباید فرض کرد که مسیر زیر صحیح است:

```text
/data/.ssh/authorized_keys
```

installer مسیر صحیح را از `/etc/passwd` استخراج کرده و Dropbear را با گزینه‌ای مشابه زیر اجرا می‌کند:

```text
-D /data/root-home/.ssh
```

## نصب public key

پس از نصب، فایل زیر را ایجاد کنید:

```text
/data/root-home/.ssh/authorized_keys
```

مجوزها باید به این شکل باشند:

```text
0700  /data/root-home/.ssh
0600  /data/root-home/.ssh/authorized_keys
```

مالکیت:

```text
root:root
```

برای مثال، از طریق root ADB shell:

```sh
mkdir -p /data/root-home/.ssh
chmod 0700 /data/root-home/.ssh
chown root:root /data/root-home/.ssh
```

سپس public key را اضافه کنید:

```sh
cat /tmp/your-public-key >> /data/root-home/.ssh/authorized_keys
```

در پایان:

```sh
chown root:root /data/root-home/.ssh/authorized_keys
chmod 0600 /data/root-home/.ssh/authorized_keys
```

یک public key معمولی ممکن است به این شکل باشد:

```text
ssh-rsa AAAAB3... user@computer
```

قسمت comment در انتهای کلید اختیاری است.

## اتصال SSH

پس از reboot:

```bash
ssh root@192.168.8.1
```

اگر IP روتر متفاوت است:

```bash
ssh root@<router-ip>
```

پورت پیش‌فرض:

```text
22
```

است.

برای استفاده از یک private key مشخص:

```bash
ssh -i /path/to/private-key root@192.168.8.1
```

برای بررسی دقیق فرآیند احراز هویت:

```bash
ssh -vvv \
    -o IdentitiesOnly=yes \
    -i /path/to/private-key \
    root@192.168.8.1
```

## اجرای دائمی پس از reboot

installer فایل‌های زیر را تغییر نمی‌دهد:

```text
/init.rc
/init.huawei.rc
```

در عوض از فایل موجود Huawei استفاده می‌کند:

```text
/system/etc/autorun.sh
```

فایل زیر توسط installer ساخته می‌شود:

```text
/system/bin/dropbear-start
```

و یک hook کوچک به `autorun.sh` اضافه می‌شود:

```sh
/system/bin/dropbear-start >/dev/null 2>&1 &
```

launcher ابتدا منتظر می‌ماند تا:

```text
br0
```

دارای IP LAN روتر شود.

به این ترتیب Dropbear قبل از آماده‌شدن رابط شبکه اجرا نمی‌شود.

پس از آماده‌شدن شبکه، Dropbear در حالت daemon عادی اجرا می‌شود.

## command line مربوط به Dropbear

launcher دائمی عملاً Dropbear را به شکل زیر اجرا می‌کند:

```sh
/system/bin/dropbear \
    -E \
    -D "$ROOT_SSH_DIR" \
    -r /system/etc/dropbear/dropbear_rsa_host_key \
    -r /system/etc/dropbear/dropbear_ecdsa_host_key \
    -r /system/etc/dropbear/dropbear_ed25519_host_key \
    -p "$IP:$PORT"
```

گزینه `-F` عمداً استفاده نمی‌شود تا Dropbear بتواند daemonize شود.

گزینه `-E` باعث می‌شود logها به stderr ارسال شوند.

## کلیدهای host

کلیدهای host در مسیر زیر ذخیره می‌شوند:

```text
/system/etc/dropbear/
```

installer کلیدهای زیر را ایجاد می‌کند:

```text
dropbear_rsa_host_key
dropbear_ecdsa_host_key
dropbear_ed25519_host_key
```

کلیدهای خصوصی با permission زیر محافظت می‌شوند:

```text
0600
```

و مالک آنها:

```text
root:root
```

است.

اگر کلیدهای host از قبل وجود داشته باشند، installer آنها را دوباره تولید نمی‌کند.

بنابراین اجرای مجدد installer باعث تغییر غیرضروری host identity نمی‌شود.

## اجرای مجدد installer

installer برای اجرای چندباره طراحی شده است.

در اولین نصب، نسخه اصلی `autorun.sh` در این مسیر ذخیره می‌شود:

```text
/system/etc/autorun.sh.dropbear.orig
```

در اجرای بعدی:

1. `autorun.sh` از نسخه اصلی بازیابی می‌شود.
2. فقط یک block مربوط به Dropbear اضافه می‌شود.
3. launcher دوباره نصب می‌شود.
4. کلیدهای host موجود حفظ می‌شوند.
5. فایل `authorized_keys` موجود حفظ می‌شود.

بنابراین با اجرای چندباره installer، hookهای متعدد Dropbear در `autorun.sh` ایجاد نمی‌شوند.

## نکته مهم: installer Dropbear را اجرا نمی‌کند

installer عمداً سرور SSH را بلافاصله اجرا نمی‌کند.

در پایان نصب باید روتر را reboot کنید.

پس از reboot روند به این شکل است:

```text
autorun.sh
    |
    +-- dropbear-start
             |
             +-- انتظار برای br0
             |
             +-- اجرای Dropbear
```

## بررسی پس از reboot

از ADB استفاده کنید:

```bash
adb connect 192.168.8.1:5555
adb root
adb shell
```

بررسی launcher:

```sh
ls -l /system/bin/dropbear-start
```

بررسی process:

```sh
ps | grep '[d]ropbear'
```

بررسی پورت 22:

```sh
busyboxx netstat -tunlp | grep ':22'
```

بررسی مسیر SSH:

```sh
ls -ld /data/root-home/.ssh
ls -l /data/root-home/.ssh/authorized_keys
```

بررسی hook دائمی:

```sh
grep -n -A12 -B2 'DROPBEAR SSH SERVER' /system/etc/autorun.sh
```

## رفع اشکال احراز هویت public key

اگر اتصال SSH برقرار می‌شود اما public key پذیرفته نمی‌شود، Dropbear را موقتاً در حالت foreground اجرا کنید.

ابتدا process فعلی Dropbear را متوقف کنید.

سپس:

```sh
/system/bin/dropbear -F -E \
    -D /data/root-home/.ssh \
    -r /system/etc/dropbear/dropbear_rsa_host_key \
    -r /system/etc/dropbear/dropbear_ecdsa_host_key \
    -r /system/etc/dropbear/dropbear_ed25519_host_key \
    -p 192.168.8.1:22
```

از سمت client:

```bash
ssh -vvv \
    -o IdentitiesOnly=yes \
    -i /path/to/private-key \
    root@192.168.8.1
```

همچنین این موارد را بررسی کنید:

```sh
ls -ld /data/root-home
ls -ld /data/root-home/.ssh
ls -l /data/root-home/.ssh/authorized_keys
```

دایرکتوری `.ssh` و فایل `authorized_keys` نباید برای کاربران دیگر قابل نوشتن باشند.

## اجرای دستی Dropbear

برای آزمایش دستی:

```sh
/system/bin/dropbear \
    -E \
    -D /data/root-home/.ssh \
    -r /system/etc/dropbear/dropbear_rsa_host_key \
    -r /system/etc/dropbear/dropbear_ecdsa_host_key \
    -r /system/etc/dropbear/dropbear_ed25519_host_key \
    -p 192.168.8.1:22
```

این روش فقط برای تست است.

اجرای دائمی از طریق:

```text
/system/bin/dropbear-start
```

انجام می‌شود.

## فایل‌های نصب‌شده روی روتر

installer فایل‌های زیر را نصب می‌کند:

```text
/system/bin/dropbear
/system/bin/dropbearkey
/system/bin/dropbear-start

/system/etc/dropbear/dropbear_rsa_host_key
/system/etc/dropbear/dropbear_ecdsa_host_key
/system/etc/dropbear/dropbear_ed25519_host_key

/system/etc/autorun.sh
/system/etc/autorun.sh.dropbear.orig
```

کلید عمومی SSH بر اساس home directory کاربر root در `/etc/passwd` ذخیره می‌شود.

## چه فایل‌هایی نصب نمی‌شوند

installer این موارد را نصب نمی‌کند:

```text
/etc/init.d/
/system/etc/init/dropbear.rc
```

و فایل‌های زیر را نیز تغییر نمی‌دهد:

```text
/init.rc
/init.huawei.rc
```

مکانیزم startup دائمی مشخصاً بر اساس `autorun.sh` موجود در firmware Huawei است.

## ملاحظات امنیتی

این پروژه یک root SSH server روی روتر فعال می‌کند.

بنابراین دسترسی کامل مدیریتی به دستگاه از طریق SSH فراهم می‌شود.

توصیه می‌شود از public-key authentication استفاده شود و private key در محل امن نگهداری شود.

پورت 22 را مستقیماً روی Internet منتشر نکنید، مگر اینکه آگاهانه ریسک‌های امنیتی آن را پذیرفته باشید.

این روتر یک پلتفرم قدیمی Android/Linux است و نباید مانند یک سیستم امنیتی مدرن و کاملاً پشتیبانی‌شده در نظر گرفته شود.

## حذف و rollback

نسخه اصلی `autorun.sh` در مسیر زیر نگهداری می‌شود:

```text
/system/etc/autorun.sh.dropbear.orig
```

برای حذف hook مربوط به Dropbear:

```sh
cp /system/etc/autorun.sh.dropbear.orig /system/etc/autorun.sh
chmod 0700 /system/etc/autorun.sh
chown root:root /system/etc/autorun.sh
```

سپس روتر را reboot کنید.

برای حذف باینری‌ها:

```sh
rm -f /system/bin/dropbear
rm -f /system/bin/dropbearkey
rm -f /system/bin/dropbear-start
```

برای حذف کلیدهای host:

```sh
rm -rf /system/etc/dropbear
```

اگر قصد حذف کلیدهای SSH کاربر را ندارید، directory مربوط به `.ssh` را حذف نکنید.

## به‌روزرسانی خودکار نسخه upstream

GitHub Actions هر هفته نسخه‌های جدید Dropbear را بررسی می‌کند.

workflow tagهایی مانند این موارد را تشخیص می‌دهد:

```text
DROPBEAR_2026.94
DROPBEAR_2026.95
DROPBEAR_2026.96
```

برای نسخه جدید، فرایند زیر به‌صورت خودکار انجام می‌شود:

```text
تشخیص نسخه جدید
       |
       v
دریافت source upstream
       |
       v
cross-compile برای ARMv7
       |
       v
بررسی باینری static
       |
       v
ساخت package
       |
       v
ساخت GitHub Release
```

Tag مربوط به Release پروژه به شکل زیر خواهد بود:

```text
DROPBEAR_<version>_B612
```

برای مثال:

```text
DROPBEAR_2026.94_B612
```

workflow زمان‌بندی‌شده روی آخرین commit از branch پیش‌فرض repository اجرا می‌شود.

## License

جزئیات license پروژه در فایل زیر قرار دارد:

```text
LICENSE
```

خود Dropbear نیز license مربوط به upstream خود را دارد. برای شرایط کامل license به source distribution رسمی Dropbear مراجعه کنید.
