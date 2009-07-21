require 'hotcocoa'
require 'lib/preferences'

require 'rexml/xmltokens'
module REXML
  class Attribute
    include ::REXML::XMLTokens
  end
end

require File.join(File.dirname(__FILE__), '..', 'vendor', 'xml-simple-1.0.12', 'lib', 'xmlsimple')
require File.join(File.dirname(__FILE__), '..', 'vendor', 'amazon-ec2-0.3.8', 'lib', 'EC2')

class SilverLining
  include HotCocoa

  def start
    @prefs = Preferences.instance

    application(:name => "Silverlining") do |app|
      app.delegate = self
      @window = window(:frame => [@prefs[:position], @prefs[:size]].flatten, :title => "Silver Lining") do |win|
        win.contentView.margin = 5

        win.will_close { exit }
        win.did_move { @prefs[:position] = [win.frame.origin.x, win.frame.origin.y] }
        win.did_resize { @prefs[:size] = [win.frame.size.width, win.frame.size.height] }

        reload_item = toolbar_item(:label => "Reload",
                                   :image => image(:named => "reload")).on_action { reload_instances }

        search_item = toolbar_item(:identifier => "Search") do |si|
          search = search_field(:frame => [0, 0, 250, 30],
                                :layout => {:align => :right, :start => false})
          search.on_action { |sender| filter_instances(search) }

          si.view = search
        end

        @toolbar = toolbar(:default => [reload_item, :flexible_space, search_item]) do |tb|
          win.toolbar = tb
        end


        win << scroll_view(:layout => {:expand => [:width, :height]}) do |scroll|
          sd = [sort_descriptor(:key => :id),
                sort_descriptor(:key => :type),
                sort_descriptor(:key => :dns_private),
                sort_descriptor(:key => :dns_public),
                sort_descriptor(:key => :launch_time),
                sort_descriptor(:key => :size),
                sort_descriptor(:key => :zone)]
          scroll << @table = table_view(:data => [], :layout => {:expand => [:width, :height]},
                                     :uses_alternating_row_background_colors => true,
                                     :delegate => self,
                                     :sort_descriptors => sd,
                                     :columns => [
                                          column(:id => :id, :title => 'id',
                                                        :sort_descriptor_prototype => sd[0]),
                                          column(:id => :type, :title => 'type'       ,
                                                        :sort_descriptor_prototype => sd[1]),
                                          column(:id => :dns_private, :title => 'private name',
                                                        :sort_descriptor_prototype => sd[2]),
                                          column(:id => :dns_public, :title => 'public name',
                                                        :sort_descriptor_prototype => sd[3]),
                                          column(:id => :launch_time, :title => 'launch',
                                                        :sort_descriptor_prototype => sd[4]),
                                          column(:id => :size, :title => 'size',
                                                        :sort_descriptor_prototype => sd[5]),
                                          column(:id => :zone, :title => 'zone',
                                                        :sort_descriptor_prototype => sd[6])]) do |table|

            table.on_double_action { launch_terminal }
          end
        end
      end
        
      if @prefs[:key] && @prefs[:secret]
        load_ec2_data
        load_instances
      else
        show_credentials_sheet(@window)
      end
    end
  end
  
  def show_credentials_sheet(window)
    f = window.frame
    
    credentialsSheet = window(:frame => [f.origin.x + (f.origin.x / 2) + 100,
                                         f.origin.y + f.size.height - 400,
                                         400, 400]) do |win|

      win << label(:text => "Key", :layout => {:start => false})
      win << @key_field = text_field(:layout => {:start => false, :expand => [:width]})

      win << label(:text => "Secret", :layout => {:start => false})
      win << @secret_field = text_field(:layout => {:start => false, :expand => [:width]})

      win << label(:text => "User", :layout => {:start => false})
      win << @user_field = text_field(:layout => {:start => false, :expand => [:width]})

      win << label(:text => "SSH Key File", :layout => {:start => false})
      win << @ssh_key_field = text_field(:layout => {:start => false, :expand => [:width]})
      
      win << button(:title => "save", :layout => {:start => false}) do |button|
        button.on_action { endSheet(win) }
      end
    end

    NSApp.beginSheet(credentialsSheet, modalForWindow:window, modalDelegate:self,
                     didEndSelector:nil,
                     contextInfo:nil)
  end
  
  def endSheet(sheet)
    @prefs[:key] = @key_field.stringValue
    @prefs[:secret] = @secret_field.stringValue
    @prefs[:user] = @user_field.stringValue
    @prefs[:ssh_key] = @ssh_key_field.stringValue

    sheet.orderOut(self)
    sheet.close
    
    load_ec2_data
    load_instances
  end

  def launch_terminal
    # launch command grabbed from elastic fox
    `/usr/bin/osascript -e 'on run argv' -e 'tell app "System Events" to set termOn to (exists process "Terminal")' -e 'set cmd to "ssh -i " & item 1 of argv & " " & item 2 of argv' -e 'if (termOn) then' -e 'tell app "Terminal" to do script cmd' -e 'else' -e 'tell app "Terminal" to do script cmd in front window' -e 'end if' -e 'tell app "Terminal" to activate' -e 'end run' #{@prefs[:ssh_key]} #{@prefs[:user]}@#{@table.dataSource.data[@table.selectedRow][:dns_public]}`
  end

  def load_ec2_data
    @ec2_data = []
    @ec2_types = Hash.new(0)
    ec2.describe_instances['reservationSet']['item'].each do |group|
      group_name = []
      group['groupSet']['item'].each do |i|
        group_name << i['groupId']
        @ec2_types[i['groupId']] += 1
      end

      group['instancesSet']['item'].each do |instance|
        @ec2_data << {:id => instance['instanceId'],
                     :type_array => group_name,
                     :dns_private => instance['privateDnsName'],
                     :dns_public => instance['dnsName'],
                     :launch_time => Time.parse(instance['launchTime']).to_s,
                     :size => instance['instanceType'],
                     :zone => instance['placement']['availabilityZone']}
      end
    end
    
    @ec2_data.sort! do |a, b|
      a[:type_array].sort! { |first, second| @ec2_types[second] <=> @ec2_types[first] }
      b[:type_array].sort! { |first, second| @ec2_types[second] <=> @ec2_types[first] }
      [a[:type_array], a[:launch_time]].flatten <=> [b[:type_array], b[:launch_time]].flatten
    end
    
    # do this at the end so we have the names sorted in order of usage
    @ec2_data.each { |d| d[:type] = d[:type_array].join(", ") }
  end

  def load_instances
    data = @table.dataSource.data
    data.clear
    @ec2_data.each { |d| data << d }
    @table.reload
  end

  def reload_instances
    load_ec2_data
    load_instances
  end

  def filter_instances(search)
    filter = search.stringValue.dup
    filter = filter.chomp.gsub(/^\s+/, '').gsub(/\s+$/, '')
    filter.gsub!(/\./, '-') if filter =~ /^[0-9\.]+$/

    data = @table.dataSource.data
    data.clear

    query = ".*#{filter}.*"
    @ec2_data.each do |instance|
      if instance[:id] =~ /#{query}/i || instance[:type_array].join(" ") =~ /#{query}/i ||
          instance[:dns_private] =~ /#{query}/i || instance[:dns_public] =~ /#{query}/i
        data << instance
      end
    end

    @table.reload
  end

  def ec2
    @ec2 ||= EC2::Base.new(:access_key_id => @prefs[:key], :secret_access_key => @prefs[:secret])    
  end

=begin
  def toolbar(toolbar, itemForItemIdentifier:id, willBeInsertedIntoToolbar:tb)
    NSLog("HERE")
    toolbar.item_for_identifier(id)
  end
  
  def toolbarAllowedItemIdentifiers(toolbar)
        NSLog("HERE2")
    toolbar.allowed_items
  end
  
  def toolbarDefaultItemIdentifiers(toolbar)
        NSLog("HERE3")
    toolbar.default_items
  end
=end
end

SilverLining.new.start
