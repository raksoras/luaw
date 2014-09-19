require ("luaw_template_lang")

function processModel(req, pathParams, model)
    model.title = "My Address"
    return model
end

debug_template = false

template = HTML{
    HEAD{
        TITLE{'Address'}
    },
   BODY {
        DIV {
            attrs{ class='address'},
            H1{ model.title:display() },
            TABLE{
                attrs {border="1"},
                TR{
                    TD{'Street'},
                    TD{
                        model.block:display(),
                        "&nbsp;",
                        model.street:display()
                    }
                },
                TR{
                    TD{'City'},
                    TD{ model.city:display() }
                },
                present(model.zip) {
                    equal(model.zip, 94539) {
                        TR{
                            TD{'County'},
                            TD{'Alameda'}
                        }
                    }                    
                },                
                TR{
                    TD{'State'},
                    TD{ model.state:display() }
                },
                TR{
                    TD{'Zip'},
                    TD{ model.zip:display() }
                },
                TR{
                    TD{'Country'},
                    TD{'USA'}
                }
            },
        },
        P{
            HR{}
        },
        DIV {
            "&copy; Luaw server 2014"
        }
    }
}


