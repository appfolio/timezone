require 'timezone/parser/zone'
require 'timezone/parser/rule'
require 'timezone/parser/data'
require 'time'

module Timezone::Parser::Zone
  # An entry from the TZData file.
  class Entry
    attr_reader :name, :format, :offset

    def initialize(name, offset, rule, format, end_date)
      @name = name
      @offset = parse_offset(offset)
      @rule = rule
      @format = format
      @end_date = end_date
    end

    # Rules that this TZData entry references.
    def rules
      return [] unless Timezone::Parser.rules[@rule]

      @rules ||= Timezone::Parser.rules[@rule].select{ |rule|
        end_date.nil? || rule.start_date < end_date
      }
    end

    # Formats for the UNTIL value in the TZData entry.
    UNTIL_FORMATS = [
      '%Y %b', # 1900 Oct
      '%Y %b %e', # 1948 May 15
    ]

    # The integer value of UNTIL with offset taken into consideration.
    def end_date
      UNTIL_FORMATS.each do |format|
        begin
          return Time.strptime(@end_date+' UTC', format+' %Z').to_i * 1_000
        rescue ArgumentError
          next
        end
      end

      nil
    end

    # def data(start_date = nil)
    #   set = [Data.new(start_date, end_date, false, offset, format)]
    def data(set = [], limit)
      previous = set.last

      additions = []

      if rules.empty?
        # TODO what if there is no end date?
        additions << Timezone::Parser::Data.new(previous && previous.end_date, end_date, false, offset, format)
      else
        if previous && previous.has_end_date?
          additions << Timezone::Parser::Data.new(previous.end_date, nil, false, offset, format)
        else
          additions << set.pop
        end
      end

      rules.each do |rule|
        additions.each_with_index do |data, i|
          sub = rule.apply(self)

          # If the rule applies.
          if sub.start_date > data.start_date && sub.start_date < data.end_date && (!limit || sub.start_date > limit)
            insert = Timezone::Parser::Data.new(
              sub.start_date,
              data.has_end_date? ? data.end_date : nil,
              sub.dst?,
              sub.offset,
              format,
              sub.utime?,
              sub.letter)

            data.end_date = insert.start_date

            additions.insert(i+1, insert)
          end
        end
      end

      set + additions
    end

    private

    def parse_offset(offset)
      offset = Time.parse(offset)
      offset.hour*60*60 + offset.min*60 + offset.sec
    end
  end
end
