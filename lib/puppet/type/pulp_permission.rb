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

  newparam(:name) do
    desc 'The name to identify the entry for resource permission in format login:resource'
    isnamevar
  end

  newparam(:resource) do
    isnamevar #part of the name
    desc "target resource"
  end

  newproperty(:permissions, :array_matching => :all) do
    desc "user roles"
    validate do |values|
      values = [values] unless values.is_a?(Array)
      raise ArgumentError, "permissions cannot be empty" if values.empty?
    end
    munge do |value|
      value=[value] unless value.is_a?(Array)
      value=value.map(&:upcase)
      value.sort
    end
    def insync?(is)
      Puppet.debug("permissions current: #{is}, should : #{should}")
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
            [ :resource, identity ]
        ]
      ],
      [
        /^(.*):(.*)$/,
        [
          [ :name, identity ],
          [ :resource, identity ]
        ]
      ]
    ]
  end

  validate do
    # if value(:name) == 'admin'
    #   raise ArgumentError, "default amdin user permssion can not be changed"
    # end
  end

end
