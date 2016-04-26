require 'puppet'
require 'openssl'
require 'puppet/util/ini_file' #this is defined in puppetlabs/inifile module, with customizable key value seperator
require 'json'


Puppet::Type.type(:pulp_user).provide(:cli) do

  desc "Manage pulp user with command line utilities"
  commands :pulpadmin => 'pulp-admin'
  commands :curl => 'curl'
  commands :grep => 'grep'

  def initialize(value={})
    super(value)
    @property_flush = {}

  end
  mk_resource_methods

  def self.instances
    login_get_cert
    pulp_server=get_server
    Puppet.debug("Retrive all users from #{pulp_server}")
    cert_path = File.expand_path("~/.pulp/user-cert.pem")
    user_list_cmd = [command(:curl),  '-s', '-k', '--cert' , cert_path,  "https://#{pulp_server}/pulp/api/v2/users/?details=true"]
    users =[]
    Puppet.debug("#{user_list_cmd}.join(' ')")
    output = execute(user_list_cmd).to_s
    Puppet.debug("output class #{output.class} value: #{output.to_json}")
    users_json= JSON.parse(output)
    #An array returned
    users_json.each do |user|
      Puppet.debug("user : #{user.to_json}")
      data_hash ={}
      data_hash[:name] =user['login']
      data_hash[:login] =user['login']
      data_hash[:roles] = user['roles'].sort
      data_hash[:display_name] = user['name']
      data_hash[:provider] = self.name
      data_hash[:ensure] = :present
      Puppet.debug("data_hash #{data_hash.to_json}")
      users << new(data_hash) unless data_hash.empty?
    end
    Puppet.debug("users : #{users.to_json}")
    users
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot get user list #{details}"
  end

  def self.prefetch(users)
    Puppet.debug("prefetch")
    instances.each do |prov|
       Puppet.debug("prov name : #{prov}")
       if r = users[prov.name]
         r.provider = prov
       end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    self.class.login_get_cert
    Puppet.debug("create with cmd: #{user_create_cmd.join(' ')}")
    execute(user_create_cmd)
    @property_hash[:ensure] = :present
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot create user : #{user_create_cmd.join(' ')}, details: #details"
  end

  def destroy
    self.class.login_get_cert
    Puppet.debug("Preparing delete command")
    cmd=user_delete_cmd
    Puppet.debug("user delete command :#{cmd}")
    execute(cmd)
    Puppet.debug("Clearing property_hash")
    @property_hash.clear
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot delete user : #{user_delet_cmd}"
  end

  def display_name=(value)
    @property_flush[:display_name] = value
  end

  def roles=(value)
    @property_flush[:roles] = value
  end

  def password=(value)
    #Do not change password, only set up once
  end

  def flush
    self.class.login_get_cert
    Puppet.debug("flush method, existing resource is #{resource}")
    options=[]
    deleted_roles=[]
    added_roles=[]
    if @property_flush
      options << '--name' <<  @property_flush[:display_name] if @property_flush[:display_name]
      if @property_flush[:roles]
        deleted_roles=@property_hash[:roles] - @property_flush[:roles]
        added_roles=@property_flush[:roles] - @property_hash[:roles]
      end
    end
    Puppet.debug("flush with command options :#{options.join(' ')}")
    unless options.empty?
      Puppet.debug("finish cert check")
      cmd=user_update_cmd(options)
      Puppet.debug("user update cmd :#{cmd}")
      execute(cmd)
    end
    change_roles(@property_hash[:login], added_roles, deleted_roles)
  end

  def change_roles(user, added_roles, deleted_roles)
    add_cmd =user_role_cmd(user, true)
    remove_cmd =user_role_cmd(user, false)

    unless added_roles.empty?
      add_role = added_roles.each do |role|
         cmd = add_cmd.dup << '--role-id' << role
         execute(cmd)
      end
    end

    unless deleted_roles.empty?
      remove_role = deleted_roles.each do |role|
         cmd = remove_cmd.dup << '--role-id' << role
         execute(cmd)
      end
    end
  end

  def user_role_cmd(user,add=true)
     add_or_delete = add ? 'add': 'remove'
     role_cmd =[command(:pulpadmin), 'auth', 'role', 'user', add_or_delete, '--login' , user]
  end

  def user_create_cmd()
    user_create=[command(:pulpadmin), 'auth', 'user', 'create',  "--login", "#{self.resource['login']}", '--name', self.resource['display_name']]
    user_create <<  '--password' << self.resource['password']  if self.resource['password']
    Puppet.debug("user_create = #{user_create}")
    user_create
  end

  def user_delete_cmd()
    [command(:pulpadmin), 'auth', 'user', "delete",  "--login", @property_hash[:login]]
  end

  def user_update_cmd()
    Puppet.debug("type :#{@property_hash}")
    [command(:pulpadmin), 'auth', 'user',  "update", "--login", @property_hash[:id] ]+options
  end
  #assume user have ~/.pulp/admin setup with auth username and password
  #[auth]
  #username:
  #password:
  def self.login_get_cert
    Puppet.debug("executing login_get_cert")
    unless is_cert_valid?
      unless @credentials
        @credentials= get_auth_credetials
      end
      login_cmd = [command(:pulpadmin), 'login', '-u', @credentials['username'], '-p', @credentials['password']]
      Puppet.debug("execute login command #{login_cmd}, cmd class #{login_cmd.length}")
      output = execute(login_cmd)
    end
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Check ~/.pulp/admin.conf for credentials, could not log in with pulpadmin: #{detail}"
  end

  def self.get_auth_credetials
    Puppet.debug("executing get_auth_credentials")
    admin_conf=File.expand_path("~/.pulp/admin.conf")
    Puppet.debug("admin.conf path : #{admin_conf}")
    admin_ini = Puppet::Util::IniFile.new(admin_conf, ':')
    cred ={}
    cred['username'] = admin_ini.get_value('auth', 'username')
    cred['password'] = admin_ini.get_value('auth', 'password')
    Puppet.debug("cred: #{cred.class} #{cred['username']}  #{cred['password']}")
    cred
  end

  def self.is_cert_valid?
    Puppet.debug("check user certificate valid")
    unless @date_after
      cert_path = File.expand_path("~/.pulp/user-cert.pem")
      if !File.exist?(cert_path)
        Puppet.debug("cannot find user certificate #{cert_path}")
        return false
      end
      raw_cert = File.read cert_path
      cert_file = OpenSSL::X509::Certificate.new raw_cert
      @date_after = cert_file.not_after
      @date_before = cert_file.not_before
    end
    current_time = Time.now
    Puppet.debug("current_time :#{current_time} @date_after : #{@date_after}")
    if current_time.to_i < @date_after.to_i - 600 && current_time.to_i > @date_before.to_i
      return true
    else
      return false
    end
  end

  def self.get_server
    host_output=execute([command(:grep), '^host', '/etc/pulp/admin/admin.conf'])
    Puppet.debug("grep host from admin.conf: #{host_output}")
    if !host_output.empty?
      host_spec=host_output.split(' ')
      Puppet.debug("host_spec: #{host_spec}")
      host=host_spec[1]
      if host.empty?
        'localhost'
      else
        host
      end
    else
      'localhost'
    end
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "cannot get pulp server host from /etc/pulp/admin/admin.conf"
  end
end
