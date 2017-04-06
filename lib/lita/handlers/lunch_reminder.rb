require 'rufus-scheduler'

module Lita
  module Handlers
    class LunchReminder < Handler
      on :loaded, :load_on_start
      def load_on_start(_payload)
        create_schedule
      end
      route(/gracias/i, command: true) do |response|
        response.reply(t(:yourwelcome, subject: response.user.mention_name))
      end
      route(/^está?a? (listo|servido) el almuerzo/i) do
        message = t(:dinner_is_served)
        notify current_lunchers_list, message
      end
      route(/write/i) do |response|
        response.reply "ok amigo"
        persist_current_lunchers
      end
      route(/qué?e? hay de postre/i) do |response|
        response.reply(t(:"todays_dessert#{1 + rand(4)}"))
      end
      route(/qué?e? hay de almuerzo/, command: true) do |response|
        response.reply(t(:todays_lunch))
      end
      route(/por\sfavor\sconsidera\sa\s([^\s]+)\s(para|en) (el|los) almuerzos?/) do |response|
        mention_name = response.matches[0][0]
        success = add_to_lunchers(mention_name)
        if success
          response.reply(t(:will_ask_daily, subject: mention_name))
        else
          response.reply(t(:already_considered, subject: mention_name))
        end
      end
      route(/por\sfavor\sconsidé?e?rame\s(para|en) los almuerzos/, command: true) do |response|
        success = add_to_lunchers(response.user.mention_name)
        if success
          response.reply(t(:will_ask_you_daily))
        else
          response.reply(t(:already_considered_you, subject: response.user.mention_name))
        end
      end
      route(/^sí$|^hoy almuerzo aquí?i?$|^si$/i, command: true) do |response|
        success = add_to_current_lunchers(response.user.mention_name)
        lunchers = current_lunchers_list.length
        if success
          case lunchers
          when 1
            response.reply(t(:current_lunchers_one))
          when 2..9
            response.reply(t(:current_lunchers_some, subject: lunchers))
          end
        else
          response.reply(t(:current_lunchers_too_many))
        end
      end
      route(/^no$|no almuerzo|^nop$/, command: true) do |response|
        remove_from_current_lunchers response.user.mention_name
        response.reply(t(:thanks_for_answering))
      end

      route(/quié?e?nes almuerzan hoy/i) do |response|
        case current_lunchers_list.length
        when 0
          response.reply(t(:no_one_lunches))
        when 1
          response.reply(t(:only_one_lunches, subject: current_lunchers_list[0]))
        when 2
          response.reply(t(:dinner_for_two,
            subject1: current_lunchers_list[0],
            subject2: current_lunchers_list[1]))
        else
          response.reply(t(:current_lunchers_list,
            subject1: current_lunchers_list.length,
            subject2: current_lunchers_list.join(', ')))
        end
      end

      route(/quié?e?nes no almuerzan hoy/i) do |response|
        response.reply(t(:wont_lunch, subject: wont_lunch.join(', ')))
      end

      route(/quié?e?nes está?a?n considerados para (el|los) almuerzos?/i) do |response|
        response.reply(lunchers_list.join(', '))
      end

      def refresh
        reset_current_lunchers
        message = t(:question, subject: luncher)
        notify(lunchers, message)
      end

      def notify(list, message)
        list.each do |luncher|
          user = Lita::User.find_by_mention_name(luncher)
          robot.send_message(Source.new(user: user), message)
        end
      end

      def add_to_lunchers(mention_name)
        redis.sadd("lunchers", mention_name)
      end

      def remove_from_lunchers(mention_name)
        redis.srem("lunchers", mention_name)
      end

      def lunchers_list
        redis.smembers("lunchers") || []
      end

      def add_to_current_lunchers(mention_name)
        if current_lunchers_list.length < 10
          redis.sadd("current_lunchers", mention_name)
          true
        else
          false
        end
      end

      def remove_from_current_lunchers(mention_name)
        redis.srem("current_lunchers", mention_name)
      end

      def persist_current_lunchers
        sw = Lita::Services::SpreadsheetWriter.new
        sw.write_new_row([Time.now.strftime("%Y-%m-%d")].concat(current_lunchers_list))
      end

      def current_lunchers_list
        redis.smembers("current_lunchers") || []
      end

      def wont_lunch
        redis.sdiff("lunchers", "current_lunchers")
      end

      def reset_current_lunchers
        redis.del("current_lunchers")
      end

      def create_schedule
        scheduler = Rufus::Scheduler.new
        scheduler.cron('00 13 * * 1-5') do
          refresh
        end
      end

      Lita.register_handler(self)
    end
  end
end
