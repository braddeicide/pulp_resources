require 'puppet'
require 'openssl'
require 'puppet/util/inifile'
require 'json'

Puppet::Type.type(:pulp_repo).provide(:cli) do

  desc "Manage pulp repo with command line utilities"
  commands :pulpadmin => 'pulp-admin'
  commands :curl => 'curl'

  def initialize(value={})
    super(value)
    @property_flush = {}
    #login fetch user certificate
    login_get_cert
  end
  mk_resource_methods

  def self.instances
    login_get_cert
    pulp_server=get_server
    Puppet.debug("Retrive all repos from #{pulp_server}")
    cert_path = File.expand_path("~/.pulp/user-cert.pem")
    repo_list_cmd = [command(:curl),  '-s', '-k', '--cert' , cert_path,  "https://#{pulp_server}/pulp/api/v2/repositories/?details=true"]
    repos =[]
    Puppet.debug("#{repo_list_cmd}.join(' ')")
    output = execute(repo_list_cmd).to_s
    Puppet.debug("output class #{output.class} value: #{output.to_json}")
    repo_json= JSON.parse(output)
    #An array returned
    repo_json.each do |repo|
      Puppet.debug("repo : #{repo.to_json}")
      data_hash ={}
      data_hash[:id] = repo['id']
      data_hash[:name] = repo['display_name']
      data_hash[:description] = repo['description']
      Puppet.debug("check importers")
      if repo['importers']
        repo['importers'].each do |importer|
          if importer['config']
            data_hash[:feed]=importer['config']['feed']
          end
        end
      end
      Puppet.debug("check destributors")
      if repo['distributors']
        repo['distributors'].each do |distributor|
          if distributor['distributor_type_id'] == 'yum_distributor'
            data_hash[:server_http] = distributor['config']['http']
            data_hash[:server_https] = distributor['config']['https']
          end
        end
      end
      data_hash[:ensure] = 'present'
      data_hash[:provider] = self.name
      repos << data_hash unless data_hash.empty?
    end
    Puppet.debug("repos : #{repos.to_json}")
    repos
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot get repo list #{details}"
  end

  def self.prefetch(repos)
    Puppet.debug("prefetch #{repos}")
    instances.each do |prov|
      Puppet.debug("prov name : #{prov}")
      if r = repos[prov.name]
        r.provider = prov
      end
    end
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    login_get_cert
    execute(repo_create_cmd)
    @property_hash[:ensure] = :present
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot create repo : #{repo_create_cmd}"
  end

  def destroy
    login_get_cert
    execute(repo_delete_cmd)
    @property_hash.clear
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot delete repo : #{repo_delet_cmd}"
  end

  def name=(value)
    @property_flush[:name] = value
  end

  def description=(value)
    @property_flush[:description] = value
  end

  def feed=(value)
    @property_flush[:feed] = value
  end

  def serve_http=(value)
    @property_flush[:serve_http] = value
  end

  def serve_https=(value)
    @property_flush[:serve_https] = value
  end

  def flush
    Puppet.debug("flush method")
    options=[]
    if @property_flush
      options << '--display-name' << @resources[:name] if @property_flush[:name]
      options << '--discription' << @resources[:description] if @property_flush[:description]
      options << '--feed' << @resources[:feed] if @property_flush[:feed]
      options << '--serve-http' << @resources[:serve_http] if @property_flush[:serve_https]
      options << '--serve-https' << @resources[:serve_http] if @property_flush[:serve_https]
    end
    unless options.empty?
      login_get_cert
      execute(repo_update_cmd(options))
    end
  end

  def repo_create_cmd()
    repo_create=[command(:pulpadmin), "#{@resources[:type]}", "repo", "create" , "--repo-id", "#{@resources[:id]}" ]
    if @resources[:feed]
      repo_create = repoo_create + ["--feed", "#{@resources[:feed]}"]
    end
    if @resources[:serve_http]
      repo_create = repoo_create + ["--server-http", "#{@resources[:serve_http]}"]
    end
    if @resources[:serve_https]
      repo_create = repoo_create + ["--server-https", "#{@resources[:serve_https]}"]
    end
    repo_create
  end

  def repo_delete_cmd()
    [command(:pulpadmin), @resources[:type], "repo", "delete", "--bg", "--repo-id", @resources[:id]]
  end

  def repo_update_cmd(options)
    [command(:pulpadmin), @resources[:type], "repo", "update","--bg", "--repo-id", @resources[:id] ]+options
  end
  #assume user have ~/.pulp/admin setup with auth username and password
  #[auth]
  #username:
  #password:
  def self.login_get_cert
    Puppet.debug("login_get_cert")
    unless is_cert_valid?
      unless @credentials
        @credentials= get_auth_credetials
      end
      login_cmd = [command(:pulpadmin), 'login', '-u', @credentials['username'], '-p', @credentials['password']]
      Puppet.debug("execute login command #{login_cmd}, cmd class #{login_cmd.length}")
      #output=exec()
      output = execute(login_cmd)
    end
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Check ~/.pulp/admin.conf for credentials, could not log in with pulpadmin: #{detail}"
  end

  def self.get_auth_credetials
    admin_conf=File.expand_path("~/.pulp/admin.conf")
    admin_ini = Puppet::Util::IniConfig::PhysicalFile.new(admin_conf)
    admin_ini.read
    cred ={}
    if (auth = admin_ini.get_section('auth'))
      if auth.entries.empty?
        raise Puppet::Error, "Check ~/.pulp/admin.conf for auth config"
      end
      cred['username'] = auth['username']
      cred['password'] = auth['password']
    end
    Puppet.debug("cred: #{cred.class} #{cred['username']}  #{cred['password']}")
    cred
  end

  def self.is_cert_valid?
    Puppet.debug("check user certificate valid")
    unless @date_after
      cert_path = File.expand_path("~/.pulp/user-cert.pem")
      if !File.exist?(cert_path)
        Puppet.debug("canot find user certificate #{cert_path}")
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
    host_output=execute(['grep', '^host', '/etc/pulp/admin/admin.conf'])
    Puppet.debug("#{host_output}")
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
