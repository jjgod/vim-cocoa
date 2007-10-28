# bootstrap.sh

mkdir -p auto/
rm -f auto/config.status auto/config.cache config.log auto/config.log
rm -f auto/config.h auto/link.log auto/link.sed auto/config.mk
touch auto/config.h
cp config.mk.dist auto/config.mk

if test ! -f configure.save; then mv configure configure.save; fi
autoconf
sed -e 's+>config.log+>auto/config.log+' -e 's+\./config.log+auto/config.log+' configure > auto/configure
chmod 755 auto/configure
mv -f configure.save configure
rm -rf autom4te.cache
rm -f auto/config.status auto/config.cache
