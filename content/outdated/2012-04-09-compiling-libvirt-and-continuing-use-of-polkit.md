+++
title = "Compiling libvirt and continuing use of polkit"
date = 2012-04-18
+++

*edit: most people will just want to Docker or similar these days*

This drove me batty for a little bit. I compiled libvirt and I couldn't get polkit to allow a non-priviledged user to use qemu:///system. So here are the notes and why this ended up happening.

First of all, whenever compiling a piece of software, I always use --prefix to make sure I don't clobber any system files managed by whatever OS you use. Personally I did this on Ubuntu.

First download the version of libvirt you want, for my project I wanted to make sure I was compatible with 0.9.4 (the whole reason I couldn't use the version available from apt):

```
$> wget http://libvirt.org/sources/libvirt-0.9.4.tar.gz
```

The instructions on libvirts site tell you to do the basic gnu configure steps, i.e. ./configure, make, make install, but this is much too simplistic in my opinion and would potentially clobber system files.

Here are my steps:

```
$> tar -xzvf libvirt-0.9.4.tar.gz
$> cd libvirt-0.9.4
$> make clean
```

And my configuration options:

```
$> ./configure --prefix=/opt/libvirt --with-polkit --with-app-armor --with-capng --with-qemu
```

For any errors you'll probably need to make sure you install certain dev packages of common things, like libapparmor-dev etc.

```
$> make
$> sudo make install
```

Now here are somethings that are screwed up after installation:

```
# permissions on the directories in the install path are wrong
$> sudo find /opt/libvirt -type d -exec chmod go+rx {} \;

# I want to use actual /var not the one in the /opt/libvirt
$> sudo rm -r /opt/libvirt/var && pushd /opt/libvirt && sudo ln -s /var && popd
```

Here's the thing with polkit that I had missed and spent many hours trying to figure out, of course it was self imposed. virsh and the Java binding Connect kept giving me this error:

```
error: Failed to connect to the hypervisor
error: authentication failed: authentication failed
```

polkit is a cool system, which I didn't know well until I ran into having to get this next thing setup. The purpose of polkit is to allow non-privileged users access to perform certain actions without the need of promoting to root via sudo. This is important if like me you want to use libvirt's Java bindings, you don't really want to run your JVM as root, do you? Anyway, polkit requires some configuration, first is that you need to define the new actions. Normally make install would do this properly, but since we specified a different --prefix, it ended up installing the action definitions in /opt/libvirt/share. To add it to the actual system just add a new link (that way if you ever reinstall, the link will point to the new file, as opposed to having to remember to copy it each time).

```
$> pushd /usr/share/polkit-1/actions && sudo ln -s /opt/libvirt/share/polkit-1/actions/org.libvirt.unix.policy && popd
```

Now install the new file that grants non-root users access to perform the libvirt actions

```
$> cat > 50-libvirt-remote-access.pkla <<END
[libvirt Management Access]
Identity=unix-group:libvirt
Action=org.libvirt.unix.manage
ResultAny=yes
ResultInactive=yes
ResultActive=yes

[libvirt Monitor Access]
Identity=unix-group:users
Action=org.libvirt.unix.monitor
ResultAny=yes
ResultInactive=yes
ResultActive=yes
END

$> sudo cp 50-libvirt-remote-access.pkla /etc/polkit-1/localauthority/50-local.d
```

Notice that the group for management is libvirt and monitoring is any user on the system. You will need to make sure both that the group exists (see /etc/group and groupadd) and that your user is a member (see id, and usermod).

With all of that setup, now you just need to make sure that your environment is setup, add this to your .bashrc or equivalent:

```
export LIBVIRT_HOME=/opt/libvirt
export PATH=$LIBVIRT_HOME/bin:$PATH
export LD_LIBRARY_PATH=$LIBVIRT_HOME/lib
export PYTHONPATH=$LIBVIRT_HOME/lib/python2.6/site-packages
```

Make sure to login or create a new terminal to reload your shell. Other things to note, I didn't mention starting libvirtd, you will need to do this. If you put things in the paths I specified this would be in /opt/libvirt/sbin/libvirtd. You probably will want this to be started automatically. If you need an upstart script, post a comment, and I can post one. Otherwise, you can just modify the one that is installed with the system to point to the proper location for everything.
