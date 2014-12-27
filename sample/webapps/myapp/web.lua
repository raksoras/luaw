luaw_webapp = {
    resourcePattern = "handler%-.*%.lua",
    viewPattern = "view%-.*%.lua",
}

Luaw.logging.file {
    name = "root",
    level = Luaw.logging.ERROR,
}

Luaw.logging.file {
    name = "com.luaw",
    level = Luaw.logging.INFO,
}

Luaw.logging.syslog {
    name = "com.luaw",
    level = Luaw.logging.WARNING,
}

--Luaw.logging.category {
--    name = 'com',
--    level = Luaw.logging.WARNING,
--    target = Luaw.logging.FILE
--}
