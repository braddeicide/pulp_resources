# use composite namevar
# example can be found https://github.com/puppetlabs/puppetlabs-java_ks
Puppet::Type.newtype(:pulp_permission) do
  @doc = <<-EOT
  Resource type for pulp user
  EOT
  ensurable do
    desc <<-EOS
      Manage a pulp user.
    EOS

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present
  end

  #this is the login/user in pulp
  newparam(:name, :namevar => true) do
    desc 'The name to identify the entry for resource permission in format login:resource'    
  end

  newparam(:pulp_resource, :namevar => true) do    
    desc "target resource"
  end

  newproperty(:permissions, :array_matching => :all) do
    desc "user roles"
    validate do |value|
      raise ArgumentError unless value.is_a?(String) and ["CREATE", "READ", "UPDATE", "EXECUTE", "DELETE"].include?(value.upcase)
    end
    munge do |value|
      Puppet.debug("munge value: #{value.upcase}")
      #value=value.upcase
      value.upcase
    end
    def insync?(is)
      Puppet.debug("permissions current: #{is.join(',')}, should : #{should.join(',')}")
      cmp_is = is.sort.join(',')
      cmp_should = should.sort.join(',')
      return cmp_is == cmp_should
    end
  end
  #title pattern methods for mapping tiles to namevars for supporting
  #composite namevars
  def self.title_patterns
    identity = lambda {|x| x}
    [

      [
        /^(.*):([a-z0-9]:(\/|\\).*)$/i,
        [
            [ :name, identity ],
            [ :pulp_resource, identity ]
        ]
      ],
      [
        /^(.*):(.*)$/,
        [
          [ :name, identity ],
          [ :pulp_resource, identity ]
        ]
      ]
    ]
  end
  
  autorequire(:pulp_user) do
    self[:name]
  end
end
