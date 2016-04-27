require 'puppet'
require 'openssl'
require 'puppet/util/ini_file' #this is defined in puppetlabs/inifile module, with customizable key value seperator
require 'json'


Puppet::Type.type(:pulp_role).provide(:cli) do

  desc "Manage pulp role with command line utilities"
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
    Puppet.debug("Retrive all roles from #{pulp_server}")
    cert_path = File.expand_path("~/.pulp/user-cert.pem")
    role_list_cmd = [command(:curl),  '-s', '-k', '--cert' , cert_path,  "https://#{pulp_server}/pulp/api/v2/roles/"]
    roles =[]
    Puppet.debug("#{role_list_cmd}.join(' ')")
    output = execute(role_list_cmd).to_s
    Puppet.debug("output class #{output.class} value: #{output.to_json}")
    roles_json= JSON.parse(output)
    #An array returned
    roles_json.each do |role|
      Puppet.debug("role : #{role.to_json}")
      data_hash ={}
      data_hash[:role] =role['id']
      data_hash[:name] =role['id']
      data_hash[:display_name] = role['display_name']
      data_hash[:description] = role['description']
      data_hash[:provider] = self.name
      data_hash[:ensure] = :present
      Puppet.debug("data_hash #{data_hash.to_json}")
      roles << new(data_hash) unless data_hash.empty?
    end
    Puppet.debug("roles : #{roles.to_json}")
    roles
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot get role list #{details}"
  end

  def self.prefetch(roles)
    Puppet.debug("prefetch")
    instances.each do |prov|      
       if r = roles[prov.name]
         r.provider = prov
       end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    self.class.login_get_cert
    cmd = role_create_cmd
    Puppet.debug("create with cmd: #{cmd.join(' ')}")
    execute(cmd)
    @property_hash[:ensure] = :present
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot create role : #{cmd.join(' ')}, details: #details"
  end

  def destroy
    self.class.login_get_cert
    Puppet.debug("Preparing delete command")
    cmd=role_delete_cmd
    Puppet.debug("role delete command :#{cmd}")
    execute(cmd)
    Puppet.debug("Clearing property_hash")
    @property_hash.clear
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot delete role : #{cmd}"
  end

  def display_name=(value)
    @property_flush[:display_name] = value
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def flush
    self.class.login_get_cert
    Puppet.debug("flush method, existing resource is #{resource}")
    options=[]
    if @property_flush
      options << '--display-name' <<  @property_flush[:display_name] if @property_flush[:display_name]
      options << '--description' <<  @property_flush[:description] if @property_flush[:description]
    end
    Puppet.debug("flush with command options :#{options.join(' ')}")
    unless options.empty?
      cmd=role_update_cmd(options)
      Puppet.debug("role update cmd :#{cmd.join(' ')}")
      execute(cmd)
    end
  end

  def role_create_cmd()
    role_create=[command(:pulpadmin), 'auth', 'role', 'create',  "--role-id", self.resource['role']]
    role_create <<  '--display-name' << self.resource['display_name']  if self.resource['display_name']
    role_create <<  '--description' << self.resource['description']  if self.resource['description']
    Puppet.debug("role_create = #{role_create}")
    role_create
  end

  def role_delete_cmd()
    [command(:pulpadmin), 'auth', 'role', "delete",  "--role-id", @property_hash[:role]]
  end

  def role_update_cmd(options)
    Puppet.debug("generate user update command  :#{@property_hash}")
    [command(:pulpadmin), 'auth', 'role',  "update", "--role-id", @property_hash[:role] ]+options
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
