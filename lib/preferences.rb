require 'singleton'

class Preferences
  include Singleton

  def initialize
    @preferences = NSUserDefaults.standardUserDefaults
    @preferences.registerDefaults(
        {
          :size => [800, 600],
          :position => [200, 200]
        }
      )
  end

  def []=(key, value)
    if value.nil?
      @preferences.removeObjectForKey(key.to_s)
    else
      @preferences.setObject(value, forKey:key.to_s)
    end
    @preferences.synchronize
  end

  def [](key)
    @preferences.objectForKey(key.to_sym)
  end
end
