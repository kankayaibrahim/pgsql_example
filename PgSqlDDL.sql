CREATE DATABASE pg_testdb
    ENCODING ='UTF-8'
    LC_COLLATE = 'Turkish_Turkey.1254'
    LC_CTYPE ='Turkish_Turkey.1254'
    TEMPLATE template0;


set timezone = 'Europe/Istanbul';


alter database pg_testdb set timezone to 'Europe/Istanbul';

CREATE EXTENSION if not exists citext;

/* email validasyonu için regex kontrolü */
create domain dmn_email as citext check( value ~'^[A-Za-z0-9._%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$');


-- yıl,ay,gün olarak aldığı parametreleri date olarak geri döner
create or replace function ymd(p_year int, p_month int, p_day int)
    returns date
    language plpgsql
as
$$
declare
    ret_ymd date;
begin
    SELECT TO_DATE(p_year::varchar || LPAD(p_month::varchar, 2, '0') || p_day::varchar, 'YYYYMMDD')
    into ret_ymd;
    return ret_ymd;
end;
$$;


--gün,ay,yıl olarak aldığı parametreleri date olarak geri döner
create or replace function dmy(p_day int, p_month int, p_year int)
    returns date
    language plpgsql
as
$$
declare
    ret_dmy date;
begin
    SELECT TO_DATE(p_year::varchar || LPAD(p_month::varchar, 2, '0') || p_day::varchar, 'YYYYMMDD')
    into ret_dmy;
    return ret_dmy;
end;
$$;

--ay,gün,yıl olarak aldığı parametreleri date olarak geri döner
create or replace function mdy(p_month int, p_day int, p_year int)
    returns date
    language plpgsql
as
$$
declare
    ret_mdy date;
begin
    SELECT TO_DATE(p_year::varchar || LPAD(p_month::varchar, 2, '0') || p_day::varchar, 'YYYYMMDD')
    into ret_mdy;
    return ret_mdy;
end;
$$;

/*
   Bulunulan günün tarihi geri dönen fonksiyon
   bazen kısaca tarih alanlarında where conditiona
   where fatura_tarih = today() yazmak isteyebiliriz.
*/
create or replace function today()
    returns date
    language plpgsql
as
$$
declare
    ret_today date;
begin
    select current_date
    into ret_today;
    return ret_today;
end;
$$;

/*
Windows makineye kurulu postgresql sunucularda Türkçe i,İ karakterlerinde upper lower fonksiyonlarında sorun oluyor
Örnek:
select upper('ibrahim') -> IBRAHIM
select lower('İBRAHİM') -> İbrahİm
bu sorunun çözümü için:
https://stackoverflow.com/questions/13029824/postgres-upper-function-on-turkish-character-does-not-return-expected-result
bu sayfada 3 öneri getirilmiş:
1) Kendiniz bir dll yazıp bunu çözebilirsiniz.
2) bir linux dağıtımına postgresql sunucunuzu kurun.
3) MSVCR100.DLL dosyasını patchleyin
 */

/* Parametre olarak geçilen string ifadeyi türkçe iı sorunsuz bir şekilde büyük harfe çevirir */
create or replace function upper_tr("varchar")
    returns "varchar" as
$body$
begin
    return upper(translate($1, 'ıi', 'Iİ'));
end;
$body$
    language 'plpgsql' volatile;

/* Parametre olarak geçilen string ifadeyi türkçe iı sorunsuz bir şekilde küçük harfe çevirir */
create or replace function lower_tr("varchar")
    returns "varchar" as
$body$
begin
    return lower(translate($1, 'Iİ', 'ıi'));
end;
$body$
    language 'plpgsql' volatile;

/* Bazen tablolarımıza kayıt olunan tarihin yıl ay gün gibi değerlerin saklanmasını isteriz.
   bu alanlara default olarak kayıt tarihinde ki değerleri verelim */
create table test_default_ymd
(
    id    serial primary key not null,
    name  varchar(64),
    year  smallint           not null default extract(year from current_date),
    month smallint           not null default extract(month from current_date),
    day   smallint           not null default extract(day from current_date)

);

insert into test_default_ymd(name)
values ('Ali');

select *
from test_default_ymd;

/*
    id, name , year, month, day
    1,  Ali,   2021,     5,  20
*/


/* Gümrük Tarife İstatistik Pozisyonu (GTİP)
   GTİP (ya da gtip, veya G.T.İ.P./g.t.i.p.),
   Gümrük Tarife İstatistik Pozisyonu'nun kısaltmasıdır.
   Ülkemizde, GTİP Gümrük Tarife Cetveli'nde 12'li koda verilen isimdir.

    İlk 4 Rakam Eşyanın Pozisyon Numarasını,
    İlk 6 Rakam Dünya Gümrük Örgütü'ne üye tüm ülkelerce kullanılan Armonize Sistem Nomanklatür kodunu,
    7-8 inci rakamlar Avrupa Birliği ülkeleri tarafından kullanılan Kombine Nomanklatür kodunu,
    9-10 uncu rakamlar farklı vergi uygulamaları nedeniyle açılan pozisyonları gösteren kodları,
    11-12 inci rakamlar ise Gümrük Tarife İstatistik (GTİP) kodlarını oluşturmaktadır.
    Kaynak: https://www.mevzuat.net/fayda/gtip-nedir-nasil-tespit-edilir.aspx



 */

/*
   Aşağıda yazılan fonksiyon bazen gtip'leri noktasız bir şekilde tutuğumuz varchar(12) alandan
   Uygun formatta aralara nokta ekleyerek görüntülememizi sağlar
*/

create or replace function fn_get_gtip_noktali(p_gtip varchar(12))
    returns varchar
    language plpgsql
as
$$
declare
    temp_gtip varchar;
    ret_gtip  varchar;
begin
    /* belki noktalı geldi? noktaları temizleyelim ve temp_gtip e aktaralım */
    SELECT replace(p_gtip, '.', '') into temp_gtip;

    select concat_ws('.',
                     SUBSTRING(temp_gtip, 0, 5),
                     SUBSTRING(temp_gtip, 5, 2),
                     SUBSTRING(temp_gtip, 7, 2),
                     SUBSTRING(temp_gtip, 9, 2),
                     SUBSTRING(temp_gtip, 11, 2)
               )
    into ret_gtip;
    return ret_gtip;
end;
$$;

select fn_get_gtip_noktali('392620000011') as gtip_noktali;
-- -> 3926.20.00.00.11

/*
    Bazı ihtiyaç duyulabilecek domainler

*/
/*
    Sadece pozitif değer girilebilecek integer alan
    Örnek yaş, yıl, miktar gibi bir değer tutuyorsunuz bu alanlara -15 gibi şey girilmemesi gerekir.
    tabi burada bu alanın zorunlu olup olmama bilgisi de önemli zorunlu değil ise kullanmayın.

*/
create domain dmn_positiveint as integer check ( value > 0 );
comment on domain dmn_positiveint is 'Number must be positive';


/*
    Sadece 0 ve pozitif değer girilebilecek integer alan
   + örnek bir sayaç alanınız var bu alan 0 olabilir ama - olamaz
    tabi burada bu alanın zorunlu olup olmama bilgisi de önemli zorunlu değil ise kullanmayın.

*/

create domain dmn_notnegativeint as integer default 0 check ( value >= 0 );
comment on domain dmn_notnegativeint is 'Number must be positive or zero';

/*
    Sadece 0 ve pozitif değer girilebilecek integer alan
    örnek bir sayaç alanınız var bu alan 0 olabilir ama - olamaz
    tabi burada bu alanın zorunlu olup olmama bilgisi de önemli zorunlu değil ise kullanmayın.

*/

create domain dmn_notnegativeint as integer default 0 check ( value >= 0 );
comment on domain dmn_notnegativeint is 'Number must be positive or zero';


/*
    Sadece 0 ve pozitif değer girilebilecek numeric alan
    Örnek kdv toplamı bu alanlara -15 gibi şey girilmemesi gerekir.
    kdv 0 olabilir ama - değer olamaz
    tabi burada bu alanın zorunlu olup olmama bilgisi de önemli zorunlu değil ise kullanmayın.

*/

create domain dmn_notnegativenumber as numeric(15, 6) default 0 check ( value >= 0 );
comment on domain dmn_notnegativenumber is 'Number must be positive or zero';

/*
    Sadece pozitif değer girilebilecek numeric alan
    Örnek sipariş toplamı -15 veya 0 gibi şey girilmemesi gerekir.
    normalde sipariş toplamı 0 veya - değer olmaması gerekir.
    tabi burada bu alanın zorunlu olup olmama bilgisi de önemli zorunlu değil ise kullanmayın.

*/
create domain dmn_positivenumber as numeric(15, 6) check ( value > 0 );
comment on domain dmn_positivenumber is 'Number must be positive';



