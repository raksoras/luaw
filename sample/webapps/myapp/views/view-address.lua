BEGIN 'html'
    BEGIN 'head'
        BEGIN 'title'
            TEXT 'Address'
        END 'title'
    END 'head'
    BEGIN 'body'
        BEGIN 'div' {class='address'}
            BEGIN 'h1'
                TEXT(model.title)
            END 'h1'
            BEGIN 'table' {border="1", margin="1px"}
                BEGIN 'tr'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT 'City'
                    END 'td'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT(model.city)
                    END 'td'
                END 'tr'
                if (model.zip == 94086) then
                    BEGIN 'tr'
                        BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                            TEXT 'County'
                        END 'td'
                        BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                            TEXT 'Santa Clara'
                        END 'td'
                    END 'tr'
                end
                BEGIN 'tr'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT 'Zip'
                    END 'td'
                    BEGIN 'td' {style="padding: 3px 3px 3px 3px"}
                        TEXT(model.zip)
                    END 'td'
                END 'tr'
            END 'table'
        END 'div'
    END 'body'
END 'html'

