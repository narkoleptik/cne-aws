require 'aws-sdk'
require 'colorize'
require 'terminal-table'

class CneEc2
  def initialize
    @ec2_client = Aws::EC2::Client.new(
      region: ENV['AWS_REGION'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )
    @ec2 = Aws::EC2::Resource.new(
      region: ENV['AWS_REGION'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )

    @elb_client = Aws::ElasticLoadBalancing::Client.new(
      region: ENV['AWS_REGION'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
    )
  end

  def list_instances(appname, env)
    output = []
    instance_count = 0
    response = @ec2_client.describe_instances(

      filters: [
        {
          name: 'tag:appname',
          values: [appname]
        },

        {
          name: 'tag:env',
          values: [env]
        }
      ]
    )

    if response.reservations.count == 0
      puts 'No instances found'.colorize(:red)
      exit 1
    end

    puts "Displaying #{appname} (#{env}) instances:".colorize(:red)

    response.reservations.each do |reserve|
      reserve.instances.each do |instance|
        output <<  [
          "#{instance.private_ip_address}".colorize(:green),
          "#{instance.instance_id}".colorize(:green),
          "#{instance.placement.availability_zone}".colorize(:green),
          "#{instance.launch_time}".colorize(:green)
        ]

        instance_count += 1
      end
    end

    table = Terminal::Table.new(
      :headings => [
        'IP'.colorize(:blue),
        'Instance ID'.colorize(:blue),
        'AZ'.colorize(:blue),
        'Creation Date'.colorize(:blue)
      ],
      :rows => output
    )

    puts table
    puts "#{instance_count} instances".colorize(:red)
    puts ''
  end

  def list_security_groups(name)
    output = []
    response = @ec2_client.describe_security_groups

    if name.empty?
      response.security_groups.each do |group|
        output << [
          "#{group.group_id}".colorize(:green),
          "#{group.group_name}".colorize(:green),
          "#{group.description}".colorize(:green)
        ]
      end

      table = Terminal::Table.new(
        :headings => [
          'Group ID'.colorize(:blue),
          'Group Name'.colorize(:blue),
          'Group Description'.colorize(:blue)
        ],
        :rows => output.sort_by! { |name| name[1] }
      )

      puts table
    else
      response.security_groups.each do |group|
        if group.group_name =~ /#{name}/
          output << [
            "#{group.group_id}".colorize(:green),
            "#{group.group_name}".colorize(:green),
            "#{group.description}".colorize(:green)
          ]
        end
      end

      if output.empty?
        puts 'No security groups found...'.colorize(:red)
        exit 1
      end

      table = Terminal::Table.new(
        :headings => [
          'Group ID'.colorize(:blue),
          'Group Name'.colorize(:blue),
          'Group Description'.colorize(:blue)
        ],
        :rows => output.sort_by! { |name| name[1] }
      )

      puts table
    end
  end

  def get_instance_info(instance_id)
    response = @ec2_client.describe_instances(
      instance_ids: [instance_id]
    )

    return response.reservations
  end

  def get_elb_names
    response = @elb_client.describe_load_balancers

    return response.load_balancer_descriptions
  end

  def display_all_elbs
    output = []

    get_elb_names.each do |elb|
      output << [
        "#{elb.scheme}".colorize(:green),
        "#{elb.load_balancer_name}".colorize(:green),
        "#{elb.dns_name}".colorize(:green),
        "#{elb.instances.count}".colorize(:green)
      ]
    end

    table = Terminal::Table.new(
      :headings => [
        'ELB Scheme'.colorize(:blue),
        'ELB Name'.colorize(:blue),
        'ELB DNS'.colorize(:blue),
        'ELB Instance Count'.colorize(:blue)
      ],
      :rows => output.sort_by! { |name| [ name[0], name[1]] }
    )

    puts table
  end

  def list_unhealthy_hosts
    unhealthy = []

    get_elb_names.each do |elb|
      response = @elb_client.describe_instance_health(
        load_balancer_name: elb.load_balancer_name
      )

      response.instance_states.each do |instance|
        if instance.state.include?('OutOfService')
          get_instance_info(instance.instance_id).each do |info|
            unhealthy << [
              "#{info.instances.first.instance_id}".colorize(:red),
              "#{info.instances.first.private_ip_address}".colorize(:red),
              "#{instance.state}".colorize(:red),
              "#{elb.load_balancer_name}".colorize(:red)
            ]
          end
        end
      end
    end

    if unhealthy.empty?
      puts 'All systems go! All ELBs are healthy!'.colorize(:green)
    else
      table = Terminal::Table.new(
        :headings => [
          'Instance ID'.colorize(:blue),
          'IP'.colorize(:blue),
          'Instance State'.colorize(:blue),
          'ELB'.colorize(:blue)
        ],
        :rows => unhealthy
      )

      puts table
    end
  end

  def terminate_instance(instance_id)
    if @ec2.instance(instance_id).exists?
      puts "Terminating #{instance_id}...".colorize(:red)

      @ec2.instance(instance_id).terminate
    end
  end

  def reboot_instance(instance_id)
    if @ec2.instance(instance_id).exists?
      puts "Rebooting #{instance_id}...".colorize(:blue)

      @ec2.instance(instance_id).reboot
    end
  end

  def stop_instance(instance_id)
    if @ec2.instance(instance_id).exists?
      puts "Stopping #{instance_id}...".colorize(:red)

      @ec2.instance(instance_id).stop
    end
  end

  def instances_per_region
		output = []
    regions = @ec2_client.describe_regions
    regions["regions"].each do |r|
      running = 0;
      stopped = 0;
      terminated = 0;
      ec2_tmp = Aws::EC2::Client.new(
        region: r["region_name"],
        access_key_id: ENV['AWS_ACCESS_KEY_ID'],
        secret_access_key: ENV['AWS_SECRET_ACCESS_KEY']
      )
      response = ec2_tmp.describe_instances()
      response.reservations.each do |r|
        case r[:instances].first[:state][:name]
        when 'running'
          running += 1
        when 'stopped'
          stopped += 1
        when 'terminated'
          terminated +=1
        end
      end

      output <<  [
        "#{r['region_name']}".colorize(:yellow),
        "#{response.reservations.count}".colorize(:yellow),
        "#{running}".colorize(:yellow),
        "#{stopped}".colorize(:yellow),
        "#{terminated}".colorize(:yellow)
      ]
    end

    table = Terminal::Table.new(
      :headings => [
        'Region'.colorize(:blue),
        'Instance Count'.colorize(:blue),
        'Running'.colorize(:blue),
        'Stoppped'.colorize(:blue),
        'Terminated'.colorize(:blue)
      ],
      :rows => output.sort_by! { |name| [ name[0], name[1]] }
    )

		table.align_column(1, :center)
		table.align_column(2, :center)
		table.align_column(3, :center)
		table.align_column(4, :center)
    puts table
  end
end
