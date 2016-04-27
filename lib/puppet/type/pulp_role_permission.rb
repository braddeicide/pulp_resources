# use composite namevar
# example can be found https://github.com/puppetlabs/puppetlabs-java_ks
Puppet::Type.newtype(:pulp_role_permission) do
  @doc = <<-EOT
  Type for role permission
  EOT
  ensurable do
    desc <<-EOS
      Manage a pulp role permission
    EOS

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present
  end

  newparam(:name) do
    desc 'The name to identify the entry for resource permission with title in format roleid:resource'
    isnamevar
  end

  newparam(:pulp_resource) do
    isnamevar #part of the name
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
end
