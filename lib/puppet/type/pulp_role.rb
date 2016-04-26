Puppet::Type.newtype(:pulp_role) do
  @doc = <<-EOT
  Resource type for pulp role
  EOT
  ensurable do
    desc <<-EOS
      Manage a pulp role.
    EOS

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    defaultto :present
  end

  newparam(:role) do
    desc 'The name to identify the entry for resource permission in format login:roleid'
    isnamevar
  end

  newproperty(:display_name) do
  end

  newproperty(:description) do
  end
end
