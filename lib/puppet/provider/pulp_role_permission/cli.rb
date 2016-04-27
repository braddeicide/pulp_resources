require 'puppet'
require 'openssl'
require 'puppet/util/ini_file' #this is defined in puppetlabs/inifile module, with customizable key value seperator
require 'json'


Puppet::Type.type(:pulp_role_permission).provide(:cli) do

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
    role_list_cmd = [command(:curl),  '-s', '-k', '--cert' , cert_path,  "https://#{pulp_server}/pulp/api/v2/roles/"]
    perms =[]
    Puppet.debug("#{role_list_cmd}.join(' ')")
    output = execute(role_list_cmd).to_s
    Puppet.debug("output class #{output.class} value: #{output.to_json}")
    roles_json= JSON.parse(output)
    #An array returned
    roles_json.each do |role|
      role_id = role['id']
      role['permissions'].each do | r_resource, rperm|
        data_hash ={}
        data_hash[:name] = role_id+':'+r_resource
        data_hash[:pulp_resource] =r_resource
        data_hash[:permissions] = normalize_perms(rperm)
        data_hash[:provider] = self.name
        data_hash[:ensure] = :present
        Puppet.debug("data_hash #{data_hash.to_json}")
        perms << new(data_hash) unless data_hash.empty?
      end
    end
    Puppet.debug("perms : #{perms.to_json}")
    perms
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot get role perm list #{details}"
  end

  # notice the difference of compsite namevalur
  def self.prefetch(resources)
    Puppet.debug("prefetch")
    perms=instances
    resources.keys.each do |name|
        Puppet.debug("name: #{name} #{resources[name]['pulp_resource']}")
        if provider = perms.find{|perm| perm.name ==name + ':'+ resources[name]['pulp_resource'] }
          resources[name].provider = provider
        end
    end
  end

  def exists?
    Puppet.debug("checking resource exists :#{@property_hash[:name]}")
    @property_hash[:ensure] == :present
  end

  def create
    self.class.login_get_cert
    Puppet.debug("pepare perm_create_cmd")
    cmd =perm_create_cmd
    Puppet.debug("create with cmd: #{perm_create_cmd.join(' ')}")
    execute(cmd)
    @property_hash[:ensure] = :present

  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot create user permission: #{cmd.join(' ')}, details: #{details}"
  end

  def destroy
    self.class.login_get_cert
    Puppet.debug("Preparing delete command")
    unless @property_hash[:permissions].empty?
      cmd=perm_revoke_cmd(@property_hash[:permissions])
      Puppet.debug("perm destroy command :#{cmd}")
      execute(cmd)
      Puppet.debug("Clearing property_hash")
    end
    @property_hash.clear
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot delete permission : #{perm_revoke_cmd}"
  end

  #property permssions
  def permissions=(value)
    Puppet.debug("permission set to :#{value.join(' ')} of class #{value.class}")
    @property_flush[:permissions] = value
  end

  def flush
    self.class.login_get_cert
    Puppet.debug("flush method, existing resource is #{resource}")
    deleted_perms=[]
    added_perms=[]
    perm_resource = @property_hash[:pulp_resource]
    if @property_flush && @property_flush[:permissions]
      Puppet.debug("@property_hash[:permissions]= #{@property_hash[:permissions].length}")
      Puppet.debug("@property_flush[:permissions]= #{@property_flush[:permissions].length}")
      deleted_perms=@property_hash[:permissions] - @property_flush[:permissions]
      Puppet.debug("deleted_perms : #{deleted_perms}")
      added_perms=@property_flush[:permissions] - @property_hash[:permissions]
      Puppet.debug("added_perms : #{added_perms}")
    end
    unless @property_flush.empty?
      name_spec = @property_hash[:name]
      Puppet.debug("name_spec: #{name_spec}")
      perm_update(@property_hash[:name].split(':')[0], perm_resource, added_perms, deleted_perms)
    end
  end

  def perm_create_cmd()
    Puppet.debug("perm_create_cmd")
    perms = self.class.normalize_perms(self.resource['permissions'])
    unless perms.empty?
      perm_create=[command(:pulpadmin), 'auth', 'permission', 'grant',  "--role-id", self.resource['name'], '--resource', self.resource['pulp_resource']]
      perms.each do |perm|
        perm_create <<  '-o' << perm.upcase
      end
    end
    Puppet.debug("perm_create = #{perm_create}")
    perm_create
  end

  def perm_revoke_cmd(perms)
    name_spec =@property_hash[:name]
    role_id = name_spec.split(':')[0]
    Puppet.debug("name_spec: #{@property_hash[:name]}")
    perm_revoke=[command(:pulpadmin), 'auth', 'permission', "revoke",  "--role-id", role_id, '--resource', self.resource['pulp_resource']]
    perms.each do |perm|
      perm_revoke <<  '-o' << perm.upcase
    end
    Puppet.debug("perm_revoke = #{perm_revoke.join(' ')}")
    perm_revoke
  end

  def perm_update(role, pulp_resource, added_perms, deleted_perms)
    added_perms.each do |perm|
      cmd=[command(:pulpadmin), 'auth', 'permission',  "grant", "--role-id", role, '--resource', pulp_resource]
      cmd << '-o' << perm.upcase
      Puppet.debug("grant permissions: #{cmd.join(' ')}")
      execute(cmd)
    end
    deleted_perms.each do |perm|
      cmd=[command(:pulpadmin), 'auth', 'permission',  "revoke", "--role-id", role, '--resource', pulp_resource]
      cmd << '-o' << perm.upcase
      Puppet.debug("revoke permissions: #{cmd.join(' ')}")
      execute(cmd)
    end
  end
  #assume user have ~/.pulp/admin setup with auth username and password
  #[auth]
  #username:
  #password:
  def self.login_get_cert
    Puppet.debug("executing login_get_cert, invoked by #{caller[0]}")
    unless is_cert_valid?
      unless @credentials
        @credentials= get_auth_credetials
      end
      login_cmd = [command(:pulpadmin), 'login', '-u', @credentials['username'], '-p', @credentials['password']]
      Puppet.debug("execute login command #{login_cmd}")
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

  def self.normalize_perms(perms)
    perms=[perms] unless perms.is_a?(Array)
    perms=perms.compact #get rid of new
    perms=perms.map(&:upcase).sort
  end
end
