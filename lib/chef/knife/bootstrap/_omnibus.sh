#
# Partial: _omnibus
#
# Functions to install Chef Server from an Ombibus package
#

package_url() {
  if [ -n "$url" ] ; then
    echo "$url"
  else
    local base="http://www.getchef.com/chef/download-server"
    if [ -n "$version" ] ; then
      local v="&v=${version}"
    fi

    echo "${base}?p=${platform}&pv=${platform_version}&m=${machine}&prerelease=${prerelease}${v}"
  fi
}

# Set the filename for a deb, based on version and machine
deb_filename() {
  filetype="deb"
  if [ $machine = "x86_64" ];
  then
    filename="chef_${version}_amd64.deb"
  else
    filename="chef_${version}_i386.deb"
  fi
}

# Set the filename for an rpm, based on version and machine
rpm_filename() {
  filetype="rpm"
  filename="chef-${version}.${machine}.rpm"
}

failed_download() {
  warn "We encountered an error downloading the package."
  echo
  exit 5
}

is_server_installed() {
  if [ -f "/opt/chef-server/bin/chef-server-ctl" ] ; then
    return 0
  elif [ -f "/opt/opscode/bin/chef-server-ctl" ] ; then
    return 0
  else
    return 1
  fi
}

perform_download() {
  case "$1" in
    wget)
      wget -O "$2" "$3" 2>/tmp/stderr || failed_download
    ;;
    curl)
      curl -L "$3" > "$2" || failed_download
    ;;
  esac
}

download_package() {
  if is_server_installed ; then
    info "Chef Server detected, skipping download"
    return 0
  fi

  local url="$(package_url)"

  banner "Downloading Chef Server package from $url to $tmp_dir/$filename"

  if exists wget;
  then
    perform_download wget "$tmp_dir/$filename" $url
  elif exists curl;
  then
    perform_download curl "$tmp_dir/$filename" $url
  else
    warn "Cannot find wget or curl - cannot install Chef Server!"
    exit 5
  fi

  info "Download complete"
}

install_package() {
  if is_server_installed ; then
    info "Chef Server detected, skipping installation"
    return 0
  fi

  banner "Installing Chef Server $version"
  case "$filetype" in
    "rpm") rpm -Uvh "$tmp_dir/$filename" ;;
    "deb") dpkg -i "$tmp_dir/$filename" ;;
  esac

  if [ "$tmp_dir" != "/tmp" ];
  then
    rm -r "$tmp_dir"
  fi
  banner "Package installed"
}

detect_info() {
  if [ -f "/opt/chef-server/bin/chef-server-ctl" ] ; then
    server_root="/opt/chef-server"
  elif [ -f "/opt/opscode/bin/chef-server-ctl" ] ; then
    server_root="/opt/opscode"
  fi

  info "Chef Server detected in $server_root"
}

patch_knife_code() {
  local check="((Gem::Version.new(Chef::VERSION) <= Gem::Version.new(\"11.12.2\")) || (Gem::Version.new(Chef::VERSION) >= Gem::Version.new(\"11.6.0\"))) ? exit(0) : exit(1)"
  local gems="$server_root/embedded/lib/ruby/gems/1.9.1/gems"
  local patched="$gems/.patched"

  if [ -f "$patched" ]; then
    info "Patched knife configure detected, skipping"
  elif echo "$script" | $server_root/embedded/bin/ruby -r chef/version; then
    info "Patching knife configure bug (CHEF-5211)"
    (cd $gems/chef-11.* && cat <<PATCH | tr "#" "\047" | patch -p1)
diff --git a/lib/chef/knife/configure.rb b/lib/chef/knife/configure.rb
index 6af3d4e..2c77bf1 100644
--- a/lib/chef/knife/configure.rb
+++ b/lib/chef/knife/configure.rb
@@ -153,6 +153,7 @@ EOH

       def guess_servername
         o = Ohai::System.new
+        o.load_plugins
         o.require_plugin #os#
         o.require_plugin #hostname#
         o[:fqdn] || #localhost#
PATCH
    touch "$patched"
  fi
}

prepare_chef_server_rb() {
  local config_file="/etc/chef-server/chef-server.rb"

  banner "Creating $config_file"
  mkdir -p "$(dirname $config_file)"
  cat <<CHEF_SERVER > "$config_file"
topology "standalone"

api_fqdn "$hostname"

rabbitmq["password"] = "$amqp_password"

chef_server_webui["enable"] = $webui_enable
chef_server_webui["web_ui_admin_default_password"] = "$webui_password"
CHEF_SERVER
  chmod 0600 "$config_file"
  info "Config file created"
}

symlink_binaries() {
  for bin in chef-client chef-solo chef-apply knife ohai ; do
    banner "Updating /usr/bin/$bin symlink"
    ln -snf $server_root/embedded/bin/$bin /usr/bin/$bin
  done ; unset bin
}

reconfigure_chef_server() {
  banner "Reconfiguring Chef Server"
  chef-server-ctl reconfigure
  info "Server reconfigured"
}

test_chef_server() {
  banner "Testing Chef Server"
  chef-server-ctl test
  info "Pedant suite finished"
}

configure_firewall() {
  if [ -x "/usr/sbin/lokkit" ] ; then
    banner "Opening TCP port 443"
    /usr/sbin/lokkit -p 443:tcp
    banner "Opening SSH port 22"
    /usr/sbin/lokkit -p 22:tcp
  fi
}
