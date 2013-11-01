# Cookbook name:: wpdeploy-wordpress
# Recipe:: default
#
# This recipe is heavily derived from Michael Basto's 'wordpress' cookbook, part of WP Chef.

include_recipe "apache2"
include_recipe "mysql::server"
include_recipe "php"
include_recipe "php::module_mysql"
include_recipe "apache2::mod_php5"

# Make sure the mysql gem is installed. This looks like it will change with
# the release of 0.10.10 and the inclusion of the new chef_gem.
# code curtesy @hectcastro
# http://tickets.opscode.com/browse/COOK-1009
gem_package "mysql" do
  action :install
end

if node.has_key?("ec2")
  server_fqdn = node['ec2']['public_hostname']
else
  server_fqdn = "localhost:8000"
end

node.set_unless['wordpress']['db']['password']          = node['mysql']['server_root_password']
node.set_unless['wordpress']['keys']['auth']            = secure_password
node.set_unless['wordpress']['keys']['secure_auth']     = secure_password
node.set_unless['wordpress']['keys']['logged_in']       = secure_password
node.set_unless['wordpress']['keys']['nonce']           = secure_password

execute "mysql-install-wp-privileges" do
  command "/usr/bin/mysql -u root -p\"#{node['mysql']['server_root_password']}\" < #{node['mysql']['conf_dir']}/wp-grants.sql"
  action :nothing
end

template "#{node['mysql']['conf_dir']}/wp-grants.sql" do
  source "grants.sql.erb"
  owner "root"
  group "root"
  mode "0600"
  variables(
    :user     => node['wordpress']['db']['user'],
    :password => node['wordpress']['db']['password'],
    :database => node['wordpress']['db']['database']
  )
  notifies :run, "execute[mysql-install-wp-privileges]", :immediately
end

execute "create #{node['wordpress']['db']['database']} database" do
  command "/usr/bin/mysqladmin -u root -p\"#{node['mysql']['server_root_password']}\" create #{node['wordpress']['db']['database']}"
  not_if do
    # Make sure gem is detected if it was just installed earlier in this recipe
    require 'rubygems'
    Gem.clear_paths
    require 'mysql'
    m = Mysql.new("localhost", "root", node['mysql']['server_root_password'])
    m.list_dbs.include?(node['wordpress']['db']['database'])
  end
  notifies :create, "ruby_block[save node data]", :immediately unless Chef::Config[:solo]
end

# save node data after writing the MYSQL root password, so that a failed chef-client run that gets this far doesn't cause an unknown password to get applied to the box without being saved in the node data.
unless Chef::Config[:solo]
  ruby_block "save node data" do
    block do
      node.save
    end
    action :create
  end
end

log "Navigate to 'http://#{server_fqdn}/wp-admin/install.php' to complete wordpress installation" do
  action :nothing
end

template "#{node['wordpress']['dir']}/wp-config.php" do
  source "wp-config.php.erb"
  owner "root"
  group "root"
  mode "0644"
  variables(
    :host            => node['wordpress']['db']['host'],
    :database        => node['wordpress']['db']['database'],
    :user            => node['wordpress']['db']['user'],
    :password        => node['wordpress']['db']['password'],
    :auth_key        => node['wordpress']['keys']['auth'],
    :secure_auth_key => node['wordpress']['keys']['secure_auth'],
    :logged_in_key   => node['wordpress']['keys']['logged_in'],
    :nonce_key       => node['wordpress']['keys']['nonce']
  )
  notifies :write, "log[Navigate to 'http://#{server_fqdn}/wp-admin/install.php' to complete wordpress installation]"
end

apache_site "000-default" do
  enable false
end

web_app "wordpress" do
  template "wordpress.conf.erb"
  docroot "#{node['wordpress']['dir']}"
  server_name server_fqdn
  server_aliases node['wordpress']['server_aliases']
end