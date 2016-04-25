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
      data_hash[:name] =repo['id']
      data_hash[:id] = repo['id']
      data_hash[:display_name] = repo['display_name']
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
            if distributor['config']['http']
              data_hash[:serve_http] = :true
            else
              data_hash[:serve_http] = :false
            end
            Puppet.debug("serve_https: #{distributor['config']['https']}" )
            if distributor['config']['https']
              data_hash[:serve_https] = :true
            else
              Puppet.debug("set serve_https to false")
              data_hash[:serve_https] = :false
            end
          end
        end
      end
      if !repo['notes'].empty?

        repo_type = repo['notes']['_repo-type']
        Puppet.debug("repo type : #{repo['notes'].to_json}")
        if repo_type.match('rpm')
          data_hash[:type] = 'rpm'
        end
        if repo_type.match('puppet')
          data_hash[:type] = 'puppet'
        end
        if repo_type.match('docker')
          data_hash[:type] = 'docker'
        end
      end
      data_hash[:provider] = self.name
      data_hash[:ensure] = :present


      Puppet.debug("data_hash #{data_hash.to_json}")
      # prov=new(
      #   :id => data_hash[:id],
      #   :display_name => data_hash[:display_name],
      #   :description => data_hash[:description],
      #   :serve_http => data_hash[:serve_http],
      #   :serve_https => data_hash[:serve_https],
      #   :ensure => :present
      # )
      repos << new(data_hash) unless data_hash.empty?
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
    Puppet.debug("Invoking create command #{self.resource.to_s}")
    self.class.login_get_cert
    Puppet.debug("create with cmd: #{repo_create_cmd.join(' ')}")
    execute(repo_create_cmd)
    @property_hash[:ensure] = :present
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot create repo : #{repo_create_cmd.join(' ')}"
  end

  def destroy
    login_get_cert
    execute(repo_delete_cmd)
    @property_hash.clear
  rescue Puppet::ExecutionFailure => details
    raise Puppet::Error, "Cannot delete repo : #{repo_delet_cmd}"
  end

  def display_name=(value)
    @property_flush[:display_name] = value
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
    Puppet.debug("flush method, existing resource is #{resource}")
    options=[]
    if @property_flush
      options << '--display-name' <<  wrap_with_quote(@property_flush[:display_name]) if @property_flush[:display_name]
      options << '--description' << wrap_with_quote(@property_flush[:description]) if @property_flush[:description]
      options << '--feed' <<  wrap_with_quote(@property_flush[:feed]) if @property_flush[:feed]
      options << '--serve-http' <<  @property_flush[:serve_https] if @property_flush[:serve_https]
      options << '--serve-https' <<  @property_flush[:serve_https] if  @property_flush[:sever_http]
    end
    Puppet.debug("flush with command options :#{options.join(' ')}")
    unless options.empty?
      self.class.login_get_cert
      Puppet.debug("finish cert check")
      cmd=repo_update_cmd(options)
      Puppet.debug("repo update cmd :#{cmd}")
      execute(cmd)
    end
  end

  def repo_create_cmd()
    Puppet.debug("generate create command #{self.resource['type']}")
    repo_create=[command(:pulpadmin), "#{self.resource['type']}", "repo", "create" , "--repo-id", "#{self.resource['id']}" ]
    Puppet.debug("repo_create = #{repo_create}") 
    if self.resource['feed']
      repo_create = repo_create + ["--feed", wrap_with_quote(self.resource['feed'])]
    end
    if self.resource['serve_http']
      repo_create = repo_create + ["--serve-http", wrap_with_quote(self.resource['serve_http'])]
    end
    if self.resource['serve_https']
      repo_create = repo_create + ["--serve-https", wrap_with_quote(self.resource['serve_https'])]
    end
    repo_create << "--display_name" <<  wrap_with_quote(self.resource['display_name']) if self.resource['display_name']
    repo_create << "--description" << wrap_with_quote(self.resource['description']) if self.resource['description']
    Puppet.debug("repo_create = #{repo_create}")
    repo_create
  end

  def repo_delete_cmd()
    [command(:pulpadmin), @resources[:type], "repo", "delete", "--bg", "--repo-id", @resources[:id]]
  end

  def repo_update_cmd(options)
    Puppet.debug("type :#{@property_hash}")
    [command(:pulpadmin), @property_hash[:type], "repo", "update","--bg", "--repo-id", @property_hash[:id] ]+options
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
    admin_ini = Puppet::Util::IniConfig::PhysicalFile.new(admin_conf, ":")
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
  
  def wrap_with_quote(param)
    Puppet.debug("wrap #{param} with quote")
    new_param= "\"#{param.to_s}\""
  end
end
