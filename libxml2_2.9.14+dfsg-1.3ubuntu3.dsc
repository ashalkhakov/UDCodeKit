-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Format: 3.0 (quilt)
Source: libxml2
Binary: libxml2, libxml2-utils, libxml2-dev, libxml2-doc, python3-libxml2
Architecture: any all
Version: 2.9.14+dfsg-1.3ubuntu3
Maintainer: Ubuntu Developers <ubuntu-devel-discuss@lists.ubuntu.com>
Uploaders:  Aron Xu <aron@debian.org>, YunQiang Su <wzssyqa@gmail.com>,
Homepage: http://xmlsoft.org
Description: GNOME XML library
 XML is a metalanguage to let you design your own markup language.
 A regular markup language defines a way to describe information in
 a certain class of documents (eg HTML). XML lets you define your
 own customized markup languages for many classes of document. It
 can do this because it's written in SGML, the international standard
 metalanguage for markup languages.
Standards-Version: 4.6.0
Vcs-Browser: https://salsa.debian.org/xml-sgml-team/libxml2
Vcs-Git: https://salsa.debian.org/xml-sgml-team/libxml2.git
Testsuite: autopkgtest
Testsuite-Triggers: build-essential, pkg-config
Build-Depends: debhelper-compat (= 13)
Build-Depends-Arch: dh-sequence-python3 <!nopython>, libicu-dev, liblzma-dev, libpython3-all-dev <!nopython>, pkg-config, python3-all-dev:any (>= 3.5) <!nopython>, rename, zlib1g-dev | libz-dev
Build-Depends-Indep: pkg-config
Package-List:
 libxml2 deb libs optional arch=any
 libxml2-dev deb libdevel optional arch=any
 libxml2-doc deb doc optional arch=all
 libxml2-utils deb text optional arch=any
 python3-libxml2 deb python optional arch=any profile=!nopython
Checksums-Sha1:
 b41615e638174b4e36845c68d4b305dd6a6b541f 2351200 libxml2_2.9.14+dfsg.orig.tar.xz
 5060f61da1c483a0a783ba3264bcc72a9fb16aa2 35692 libxml2_2.9.14+dfsg-1.3ubuntu3.debian.tar.xz
Checksums-Sha256:
 4fe913dec8b1ab89d13b489b419a8203176ea39e931eaa0d25b17eafb9c279e9 2351200 libxml2_2.9.14+dfsg.orig.tar.xz
 59fc09961398b137ea55b3a8ebbe3acb1522de8dc54a94ead220e1dbb88762ea 35692 libxml2_2.9.14+dfsg-1.3ubuntu3.debian.tar.xz
Files:
 bbcae2f48d1c9b1413ef953ce87e9346 2351200 libxml2_2.9.14+dfsg.orig.tar.xz
 1421d19cac29afaf9ff9dff01612b228 35692 libxml2_2.9.14+dfsg-1.3ubuntu3.debian.tar.xz
Original-Maintainer: Debian XML/SGML Group <debian-xml-sgml-pkgs@lists.alioth.debian.org>

-----BEGIN PGP SIGNATURE-----

iQJOBAEBCgA4FiEErEg/aN5yj0PyIC/KVo0w8yGyEz0FAmYIyLMaHHN0ZXZlLmxh
bmdhc2VrQHVidW50dS5jb20ACgkQVo0w8yGyEz3CPhAAmArEvPo7NT6hKKzEKIRH
AvJ/+VkNBX+aV67Y7YpwDRIagjRo83ZH8Em8hNkIjPknv3GeoEKFVYo6PoGlEic4
zV+lM+3m/uKQIa1iL2P26YefZNFUUQ+I9Anz3Q4rUaonkETpzOyd3ciT0lRXRTjb
ItDAMyVGabvu7ZXJcAC20gtbpYMuBx9RIiARo1y3ppwSsAPcEDv/YeEE0DDMQc8l
qE3QnVzgGhlqPFJp2reL9msxLlQe8dcilpZtNsjvZtvc50jWCMadiX8mPlJPgtg+
HHQRmSAnZ+GWJ5kKYWFKtH5UBANEHMJkeT6cwjN+UpjGa879RY2NTB7n/cOZ2HUp
ANqhxjJ1LUlCnikWLpbxut2WLPT/j/gQ8JJN0iLD9peT1dq9CweQ7QFAPNxc9cjT
GOXfaEYPvpdq7iQMVGrX0hOx/ovWZ0yk2gTnanvYAzwJjjHFYyu+2AM2we+a1kgh
4c+c5ih6BHCWR/3CkFdgGJ57jirwLfNGB5Ei7wUm+bOF9+U5na6Ww4Xua7hiJSNu
zWN6oQj3MGgqwfBVFuIpxc4wJu7/zOwXLUYfxOBgEjz1bYlsRVFGZszdMLZ4/N+m
mys5J7lvXhTlKEqcrcly4oGu2Ihu3y5u2RAc/PKV5CsM4jOIvYSBizoPHyc7hAFe
Souiw+nMA805QMgps4usPas=
=KBhx
-----END PGP SIGNATURE-----
