# frozen_string_literal: true

module Crawlscope
  class Schemas
    # Draft 4 omits date; the native Draft 3 format checks real calendar dates.
    DATE_OR_DATE_TIME = {
      anyOf: [
        {type: "string", format: "date-time"},
        {"$schema" => "http://json-schema.org/draft-03/schema#", "type" => "string", "format" => "date"}
      ]
    }.freeze

    FAQ_PAGE = {
      "type" => "object",
      "required" => ["@context", "@type", "mainEntity"],
      "properties" => {
        "@context" => {"const" => "https://schema.org"},
        "@type" => {"const" => "FAQPage"},
        "mainEntity" => {
          "type" => "array",
          "minItems" => 1,
          "items" => {"$ref" => "#/definitions/Question"}
        }
      },
      "definitions" => {
        "Question" => {
          "type" => "object",
          "required" => ["@type", "name", "acceptedAnswer"],
          "properties" => {
            "@type" => {"const" => "Question"},
            "name" => {"type" => "string"},
            "acceptedAnswer" => {"$ref" => "#/definitions/Answer"}
          }
        },
        "Answer" => {
          "type" => "object",
          "required" => ["@type", "text"],
          "properties" => {
            "@type" => {"const" => "Answer"},
            "text" => {"type" => "string"}
          }
        }
      }
    }.freeze

    ARTICLE = {
      type: "object",
      required: ["@type", "headline"],
      properties: {
        "@type" => {enum: ["Article", "NewsArticle", "BlogPosting"]},
        :headline => {type: "string", maxLength: 110},
        :image => {type: "string", format: "uri"},
        :datePublished => {type: "string", format: "date-time"},
        :dateModified => {type: "string", format: "date-time"},
        :author => {type: "object"},
        :publisher => {type: "object"}
      }
    }.freeze

    ORGANIZATION = {
      type: "object",
      required: ["@type", "name"],
      properties: {
        "@type" => {const: "Organization"},
        :name => {type: "string"},
        :url => {type: "string", format: "uri"},
        :logo => {
          anyOf: [
            {type: "string", format: "uri"},
            {
              type: "object",
              required: ["@type", "url"],
              properties: {
                "@type" => {const: "ImageObject"},
                :url => {type: "string", format: "uri"}
              }
            }
          ]
        },
        :description => {type: "string"}
      }
    }.freeze

    IMAGE_OBJECT = {
      type: "object",
      required: ["@type"],
      properties: {
        "@type" => {const: "ImageObject"},
        :url => {type: "string", format: "uri"},
        :contentUrl => {type: "string", format: "uri"},
        :thumbnail => {type: ["string", "object"]}
      }
    }.freeze

    OFFER = {
      type: "object",
      additionalProperties: true,
      required: ["@type"],
      properties: {
        "@type" => {const: "Offer"},
        :name => {type: ["string", "null"]},
        :price => {type: ["string", "number"]},
        :priceCurrency => {type: ["string", "null"]},
        :priceSpecification => {type: ["object", "null"]},
        :availability => {type: "string"},
        :shippingDetails => {type: "object"},
        :hasMerchantReturnPolicy => {type: "boolean"},
        :merchantReturnPolicy => {type: "object"},
        :url => {type: "string", format: "uri"},
        :eligibleQuantity => {type: "object"},
        :additionalProperty => {type: "array", items: {type: "object"}}
      }
    }.freeze

    RATING = {
      type: "object",
      required: ["@type", "ratingValue"],
      properties: {
        "@type" => {const: "Rating"},
        :ratingValue => {type: ["string", "number"]},
        :bestRating => {type: ["string", "number"]},
        :worstRating => {type: ["string", "number"]}
      }
    }.freeze

    REVIEW = {
      type: "object",
      required: ["@type", "itemReviewed"],
      properties: {
        "@type" => {const: "Review"},
        :itemReviewed => {type: "object"},
        :reviewRating => RATING,
        :author => {type: ["object", "string"]},
        :datePublished => DATE_OR_DATE_TIME,
        :reviewBody => {type: "string"}
      }
    }.freeze

    REVIEW_SNIPPET = {
      type: "object",
      required: ["@type", "reviewRating"],
      properties: {
        "@type" => {const: "Review"},
        :reviewRating => RATING,
        :author => {type: ["object", "string"]},
        :reviewBody => {type: "string"},
        :datePublished => DATE_OR_DATE_TIME
      }
    }.freeze

    AGGREGATE_RATING = {
      type: "object",
      required: ["@type"],
      properties: {
        "@type" => {const: "AggregateRating"},
        :ratingValue => {type: ["string", "number"]},
        :ratingCount => {type: "integer"},
        :reviewCount => {type: "integer"},
        :bestRating => {type: ["string", "number"]},
        :worstRating => {type: ["string", "number"]}
      }
    }.freeze

    SOFTWARE_APPLICATION = {
      type: "object",
      required: ["@type", "name"],
      properties: {
        "@type" => {const: "SoftwareApplication"},
        :name => {type: "string"},
        :applicationCategory => {type: "string"},
        :description => {type: "string"},
        :offers => {
          anyOf: [
            OFFER,
            {type: "array", items: OFFER}
          ]
        },
        :featureList => {type: ["string", "array"]},
        :aggregateRating => AGGREGATE_RATING,
        :review => REVIEW_SNIPPET
      }
    }.freeze

    WEB_APPLICATION = {
      type: "object",
      required: ["@type", "name"],
      properties: {
        "@type" => {const: "WebApplication"},
        :name => {type: "string"},
        :applicationCategory => {type: "string"},
        :description => {type: "string"},
        :operatingSystem => {type: "string"},
        :url => {type: "string", format: "uri"},
        :offers => {
          anyOf: [
            OFFER,
            {type: "array", items: OFFER}
          ]
        },
        :featureList => {type: ["string", "array"]},
        :aggregateRating => AGGREGATE_RATING,
        :review => REVIEW_SNIPPET
      }
    }.freeze

    HOW_TO = {
      type: "object",
      required: ["@type", "name", "step"],
      properties: {
        "@type" => {const: "HowTo"},
        :name => {type: "string"},
        :description => {type: "string"},
        :step => {
          type: "array",
          minItems: 1,
          items: {
            type: "object",
            required: ["@type", "name", "text"],
            properties: {
              "@type" => {const: "HowToStep"},
              :name => {type: "string"},
              :text => {type: "string"},
              :position => {type: "integer", minimum: 1}
            }
          }
        }
      }
    }.freeze

    CONTACT_PAGE = {
      type: "object",
      required: ["@type", "name"],
      properties: {
        "@type" => {const: "ContactPage"},
        :name => {type: "string"},
        :description => {type: "string"},
        :url => {type: "string", format: "uri"}
      }
    }.freeze

    PRODUCT = {
      type: "object",
      required: ["@type", "name"],
      properties: {
        "@type" => {const: "Product"},
        :name => {type: "string"},
        :image => {
          anyOf: [
            {type: "string", format: "uri"},
            IMAGE_OBJECT,
            {type: "array", items: {anyOf: [{type: "string", format: "uri"}, IMAGE_OBJECT]}}
          ]
        },
        :description => {type: "string"},
        :offers => {
          anyOf: [
            OFFER,
            {type: "array", items: OFFER}
          ]
        }
      }
    }.freeze

    RECIPE = {
      type: "object",
      required: ["@type", "name"],
      properties: {
        "@type" => {const: "Recipe"},
        :name => {type: "string"},
        :image => {type: ["string", "array"]},
        :recipeIngredient => {type: "array", items: {type: "string"}},
        :recipeInstructions => {type: ["string", "array"]}
      }
    }.freeze

    EVENT = {
      type: "object",
      required: ["@type", "name", "startDate"],
      properties: {
        "@type" => {const: "Event"},
        :name => {type: "string"},
        :startDate => {type: "string", format: "date-time"},
        :endDate => {type: "string", format: "date-time"},
        :location => {type: "object"}
      }
    }.freeze

    VIDEO_OBJECT = {
      type: "object",
      required: ["@type", "name", "description"],
      properties: {
        "@type" => {const: "VideoObject"},
        :name => {type: "string"},
        :description => {type: "string"},
        :thumbnailUrl => {type: "string", format: "uri"},
        :uploadDate => {type: "string", format: "date-time"}
      }
    }.freeze

    WEBSITE = {
      type: "object",
      required: ["@type"],
      properties: {
        "@type" => {const: "WebSite"},
        :name => {type: "string"},
        :url => {type: "string", format: "uri"},
        :potentialAction => {type: "object"}
      }
    }.freeze

    BREADCRUMB_LIST = {
      type: "object",
      required: ["@type", "itemListElement"],
      properties: {
        "@type" => {const: "BreadcrumbList"},
        :itemListElement => {
          type: "array",
          minItems: 1,
          items: {
            type: "object",
            required: ["@type", "position", "name", "item"],
            properties: {
              "@type" => {const: "ListItem"},
              :position => {type: "integer", minimum: 1},
              :name => {type: "string"},
              :item => {type: "string", format: "uri"}
            }
          }
        }
      }
    }.freeze

    WEB_PAGE = {
      type: "object",
      required: ["@type"],
      properties: {
        "@type" => {const: "WebPage"}
      }
    }.freeze

    JOB_POSTING = {
      type: "object",
      additionalProperties: true,
      required: ["@type", "title", "description", "datePosted", "hiringOrganization"],
      properties: {
        "@context" => {enum: ["https://schema.org", "https://schema.org/"]},
        "@type" => {const: "JobPosting"},
        :title => {type: "string"},
        :description => {type: "string"},
        :identifier => {type: "object"},
        :datePosted => {type: "string"},
        :validThrough => {type: "string"},
        :employmentType => {
          anyOf: [
            {type: "string"},
            {type: "array", minItems: 1, items: {type: "string"}}
          ]
        },
        :directApply => {type: "boolean"},
        :hiringOrganization => {
          type: "object",
          required: ["@type", "name"],
          properties: {
            "@type" => {const: "Organization"},
            :name => {type: "string"},
            :sameAs => {type: "string", format: "uri"},
            :logo => {type: "string", format: "uri"}
          }
        },
        :applicantLocationRequirements => {
          anyOf: [
            {type: "object"},
            {type: "array", minItems: 1, items: {type: "object"}}
          ]
        },
        :jobLocationType => {type: "string"},
        :jobLocation => {
          anyOf: [
            {type: "object"},
            {type: "array", minItems: 1, items: {type: "object"}}
          ]
        },
        :baseSalary => {type: "object"}
      },
      anyOf: [
        {required: ["jobLocation"]},
        {required: ["jobLocationType", "applicantLocationRequirements"]}
      ]
    }.freeze

    def self.schemas
      {
        "FAQPage" => FAQ_PAGE,
        "Article" => ARTICLE,
        "NewsArticle" => ARTICLE,
        "BlogPosting" => ARTICLE,
        "Organization" => ORGANIZATION,
        "SoftwareApplication" => SOFTWARE_APPLICATION,
        "WebApplication" => WEB_APPLICATION,
        "HowTo" => HOW_TO,
        "ContactPage" => CONTACT_PAGE,
        "Product" => PRODUCT,
        "Review" => REVIEW,
        "WebSite" => WEBSITE,
        "BreadcrumbList" => BREADCRUMB_LIST,
        "Recipe" => RECIPE,
        "Event" => EVENT,
        "VideoObject" => VIDEO_OBJECT,
        "WebPage" => WEB_PAGE,
        "JobPosting" => JOB_POSTING
      }
    end
  end
end
